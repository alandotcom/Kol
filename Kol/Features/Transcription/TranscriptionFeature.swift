//
//  TranscriptionFeature.swift
//  Kol
//
//  Created by Kit Langton on 1/24/25.
//

import AppKit
import Carbon
import ComposableArchitecture
import Foundation
import WhisperKit

private let transcriptionFeatureLogger = KolLog.transcription

private let maxVocabularyHints = 30

@Reducer
struct TranscriptionFeature {
  @ObservableState
  struct State: Equatable {
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    var isPrewarming: Bool = false
    var error: String?
    var recordingStartTime: Date?
    var meter: Meter = .init(averagePower: 0, peakPower: 0)
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var resolvedLanguage: String?
    var capturedScreenContext: String?
    var capturedCursorContext: CursorContext?
    var capturedVocabulary: [String]?
    var capturedIDEContext: IDEContext?
    var contextUpdateCount: Int = 0
    @Shared(.kolSettings) var kolSettings: KolSettings
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  }

  enum Action {
    case task
    case audioLevelUpdated(Meter)

    // Hotkey actions
    case hotKeyPressed
    case hotKeyReleased

    // Recording flow
    case startRecording
    case stopRecording

    // Cancel/discard flow
    case cancel   // Explicit cancellation with sound
    case discard  // Silent discard (too short/accidental)

    // Transcription result flow
    case transcriptionResult(String, URL)
    case transcriptionError(Error, URL?)

    // Context refresh during recording
    case contextRefreshTick
    case contextRefreshed(CursorContext?, String?, [String]?)

    // Model availability
    case modelMissing
  }

  enum CancelID {
    case metering
    case recordingCleanup
    case transcription
    case contextRefresh
  }

  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.soundEffects) var soundEffect
  @Dependency(\.sleepManagement) var sleepManagement
  @Dependency(\.date.now) var now
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.llmPostProcessing) var llmPostProcessing
  @Dependency(\.keychain) var keychain
  @Dependency(\.screenContext) var screenContext
  @Dependency(\.vocabularyCache) var vocabularyCache
  @Dependency(\.ideContext) var ideContext

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Starts two concurrent effects:
        // 1) Observing audio meter
        // 2) Monitoring hot key events
        // 3) Priming the recorder for instant startup
        return .merge(
          startMeteringEffect(),
          startHotKeyMonitoringEffect(),
          warmUpRecorderEffect()
        )

      // MARK: - Metering

      case let .audioLevelUpdated(meter):
        state.meter = meter
        return .none

      // MARK: - HotKey Flow

      case .hotKeyPressed:
        // If we're transcribing, send a cancel first. Otherwise start recording immediately.
        // We'll decide later (on release) whether to keep or discard the recording.
        return handleHotKeyPressed(isTranscribing: state.isTranscribing)

      case .hotKeyReleased:
        // If we're currently recording, then stop. Otherwise, just cancel
        // the delayed "startRecording" effect if we never actually started.
        return handleHotKeyReleased(isRecording: state.isRecording)

      // MARK: - Recording Flow

      case .startRecording:
        return handleStartRecording(&state)

      case .stopRecording:
        return handleStopRecording(&state)

      // MARK: - Transcription Results

      case let .transcriptionResult(result, audioURL):
        return handleTranscriptionResult(&state, result: result, audioURL: audioURL)

      case let .transcriptionError(error, audioURL):
        return handleTranscriptionError(&state, error: error, audioURL: audioURL)

      case .modelMissing:
        return .none

      // MARK: - Context Refresh During Recording

      case .contextRefreshTick:
        guard state.isRecording else { return .none }
        let bundleID = state.sourceAppBundleID
        return .run { [screenContext, vocabularyCache] send in
          let cursor = await MainActor.run {
            screenContext.captureCursorContext(bundleID)
          }
          let flatText: String?
          if let cursorText = cursor?.flatText {
            flatText = cursorText
          } else {
            flatText = await MainActor.run {
              screenContext.captureVisibleText(bundleID)
            }
          }
          var vocabulary: [String]?
          if let text = flatText, !text.isEmpty {
            let vocab = VocabularyExtractor.extract(from: text)
            vocabularyCache.merge(vocab)
            vocabulary = vocabularyCache.topTerms(maxVocabularyHints)
          }
          await send(.contextRefreshed(cursor, flatText, vocabulary))
        }

      case let .contextRefreshed(cursor, flatText, vocabulary):
        guard state.isRecording else { return .none }
        if let cursor {
          state.capturedCursorContext = cursor
          state.capturedScreenContext = cursor.flatText
        } else if let flatText {
          state.capturedCursorContext = nil
          state.capturedScreenContext = flatText
        }
        if let vocabulary {
          state.capturedVocabulary = vocabulary
        }
        state.contextUpdateCount += 1
        return .none

      // MARK: - Cancel/Discard Flow

      case .cancel:
        // Only cancel if we're in the middle of recording, transcribing, or post-processing
        guard state.isRecording || state.isTranscribing else {
          return .none
        }
        return handleCancel(&state)

      case .discard:
        // Silent discard for quick/accidental recordings
        guard state.isRecording else {
          return .none
        }
        return handleDiscard(&state)
      }
    }
  }
}

// MARK: - Effects: Metering & HotKey

private extension TranscriptionFeature {
  /// Effect to begin observing the audio meter.
  func startMeteringEffect() -> Effect<Action> {
    .run { send in
      for await meter in await recording.observeAudioLevel() {
        await send(.audioLevelUpdated(meter))
      }
    }
    .cancellable(id: CancelID.metering, cancelInFlight: true)
  }

  /// Effect to start monitoring hotkey events through the `keyEventMonitor`.
  func startHotKeyMonitoringEffect() -> Effect<Action> {
    .run { send in
      var hotKeyProcessor: HotKeyProcessor = .init(hotkey: HotKey(key: nil, modifiers: [.option]))
      @Shared(.isSettingHotKey) var isSettingHotKey: Bool
      @Shared(.kolSettings) var kolSettings: KolSettings

      // Handle incoming input events (keyboard and mouse)
      let token = keyEventMonitor.handleInputEvent { inputEvent in
        // Skip if the user is currently setting a hotkey
        if isSettingHotKey {
          return false
        }

        // Always keep hotKeyProcessor in sync with current user hotkey preference
        hotKeyProcessor.hotkey = kolSettings.hotkey
        let useDoubleTapOnly = kolSettings.doubleTapLockEnabled && kolSettings.useDoubleTapOnly
        hotKeyProcessor.doubleTapLockEnabled = kolSettings.doubleTapLockEnabled
        hotKeyProcessor.useDoubleTapOnly = useDoubleTapOnly
        hotKeyProcessor.minimumKeyTime = kolSettings.minimumKeyTime

        switch inputEvent {
        case .keyboard(let keyEvent):
          // If Escape is pressed with no modifiers while idle, let's treat that as `cancel`.
          if keyEvent.key == .escape, keyEvent.modifiers.isEmpty,
             hotKeyProcessor.state == .idle
          {
            Task { await send(.cancel) }
            return false
          }

          // Process the key event
          switch hotKeyProcessor.process(keyEvent: keyEvent) {
          case .startRecording:
            // If double-tap lock is triggered, we start recording immediately
            if hotKeyProcessor.state == .doubleTapLock {
              Task { await send(.startRecording) }
            } else {
              Task { await send(.hotKeyPressed) }
            }
            // If the hotkey is purely modifiers, return false to keep it from interfering with normal usage
            // But if useDoubleTapOnly is true, always intercept the key
            return useDoubleTapOnly || keyEvent.key != nil

          case .stopRecording:
            Task { await send(.hotKeyReleased) }
            return false // or `true` if you want to intercept

          case .cancel:
            Task { await send(.cancel) }
            return true

          case .discard:
            Task { await send(.discard) }
            return false // Don't intercept - let the key chord reach other apps

          case .none:
            // If we detect repeated same chord, maybe intercept.
            if let pressedKey = keyEvent.key,
               pressedKey == hotKeyProcessor.hotkey.key,
               keyEvent.modifiers == hotKeyProcessor.hotkey.modifiers
            {
              return true
            }
            return false
          }

        case .mouseClick:
          // Process mouse click - for modifier-only hotkeys, this may cancel/discard
          switch hotKeyProcessor.processMouseClick() {
          case .cancel:
            Task { await send(.cancel) }
            return false // Don't intercept the click itself
          case .discard:
            Task { await send(.discard) }
            return false // Don't intercept the click itself
          case .startRecording, .stopRecording, .none:
            return false
          }
        }
      }

      defer { token.cancel() }

      await withTaskCancellationHandler {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
        }
      } onCancel: {
        token.cancel()
      }
    }
  }

  func warmUpRecorderEffect() -> Effect<Action> {
    .run { _ in
      await recording.warmUpRecorder()
    }
  }
}

// MARK: - HotKey Press/Release Handlers

private extension TranscriptionFeature {
  func handleHotKeyPressed(isTranscribing: Bool) -> Effect<Action> {
    // If already transcribing, cancel first. Otherwise start recording immediately.
    let maybeCancel = isTranscribing ? Effect.send(Action.cancel) : .none
    let startRecording = Effect.send(Action.startRecording)
    return .merge(maybeCancel, startRecording)
  }

  func handleHotKeyReleased(isRecording: Bool) -> Effect<Action> {
    // Always stop recording when hotkey is released
    return isRecording ? .send(.stopRecording) : .none
  }
}

// MARK: - Recording Handlers

private extension TranscriptionFeature {
  func handleStartRecording(_ state: inout State) -> Effect<Action> {
    guard state.modelBootstrapState.isModelReady else {
      return .merge(
        .send(.modelMissing),
        .run { _ in soundEffect.play(.cancel) }
      )
    }
    state.isRecording = true
    let startTime = now
    state.recordingStartTime = startTime
    
    // Capture the active application
    if let activeApp = NSWorkspace.shared.frontmostApplication {
      state.sourceAppBundleID = activeApp.bundleIdentifier
      state.sourceAppName = activeApp.localizedName
    }

    // Capture screen context for LLM post-processing (synchronous AX call)
    if state.kolSettings.llmPostProcessingEnabled && state.kolSettings.llmScreenContextEnabled {
      // Prefer structured cursor context; fall back to flat capture
      if let cursor = screenContext.captureCursorContext(state.sourceAppBundleID) {
        state.capturedCursorContext = cursor
        state.capturedScreenContext = cursor.flatText
      } else {
        state.capturedCursorContext = nil
        state.capturedScreenContext = screenContext.captureVisibleText(state.sourceAppBundleID)
      }

      // Extract vocabulary from screen text and merge into persistent cache
      if let text = state.capturedScreenContext, !text.isEmpty {
        let vocab = VocabularyExtractor.extract(from: text)
        vocabularyCache.merge(vocab)
        state.capturedVocabulary = vocabularyCache.topTerms(maxVocabularyHints)
      } else {
        state.capturedVocabulary = nil
      }
    } else {
      state.capturedScreenContext = nil
      state.capturedCursorContext = nil
      state.capturedVocabulary = nil
    }

    // Capture IDE context (open file names) for code editors
    // Only when LLM post-processing and screen context are enabled (same gate as screen context above)
    if state.kolSettings.llmPostProcessingEnabled && state.kolSettings.llmScreenContextEnabled,
       PromptLayers.appContextCategory(for: state.sourceAppBundleID) == .code,
       let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
      let tabTitles = ideContext.extractTabTitles(pid)
      if !tabTitles.isEmpty {
        let ide = IDEContext(openFileNames: tabTitles)
        state.capturedIDEContext = ide
        // Merge file names into vocabulary cache
        let fileVocab = VocabularyExtractor.Result(properNouns: [], identifiers: [], fileNames: tabTitles)
        vocabularyCache.merge(fileVocab)
        state.capturedVocabulary = vocabularyCache.topTerms(maxVocabularyHints)
        transcriptionFeatureLogger.info("IDE context: \(tabTitles.count) tab(s), language: \(ide.detectedLanguage ?? "unknown")")
      } else {
        state.capturedIDEContext = nil
      }
    } else {
      state.capturedIDEContext = nil
    }

    state.contextUpdateCount = 0
    transcriptionFeatureLogger.notice("Recording started at \(startTime.ISO8601Format())")

    // Prevent system sleep during recording
    let startRecordingEffect: Effect<Action> = .merge(
      .cancel(id: CancelID.recordingCleanup),
      .run { [sleepManagement, preventSleep = state.kolSettings.preventSystemSleep] _ in
        // Play sound immediately for instant feedback
        soundEffect.play(.startRecording)

        if preventSleep {
          await sleepManagement.preventSleep(reason: "Kol Voice Recording")
        }
        await recording.startRecording()
      }
    )

    // Start periodic context refresh during recording (1s interval)
    let shouldRefreshContext = state.kolSettings.llmPostProcessingEnabled
      && state.kolSettings.llmScreenContextEnabled
    guard shouldRefreshContext else {
      return startRecordingEffect
    }

    let contextRefreshEffect: Effect<Action> = .run { send in
      while !Task.isCancelled {
        try await Task.sleep(for: .seconds(1))
        await send(.contextRefreshTick)
      }
    }
    .cancellable(id: CancelID.contextRefresh, cancelInFlight: true)

    return .merge(startRecordingEffect, contextRefreshEffect)
  }

  func handleStopRecording(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    let contextUpdates = state.contextUpdateCount
    if contextUpdates > 0 {
      transcriptionFeatureLogger.info("Context refreshed \(contextUpdates) time(s) during recording")
    }

    let stopTime = now
    let startTime = state.recordingStartTime
    let duration = startTime.map { stopTime.timeIntervalSince($0) } ?? 0

    let decision = RecordingDecisionEngine.decide(
      .init(
        hotkey: state.kolSettings.hotkey,
        minimumKeyTime: state.kolSettings.minimumKeyTime,
        recordingStartTime: state.recordingStartTime,
        currentTime: stopTime
      )
    )

    let startStamp = startTime?.ISO8601Format() ?? "nil"
    let stopStamp = stopTime.ISO8601Format()
    let minimumKeyTime = state.kolSettings.minimumKeyTime
    let hotkeyHasKey = state.kolSettings.hotkey.key != nil
    transcriptionFeatureLogger.notice(
      "Recording stopped duration=\(String(format: "%.3f", duration))s start=\(startStamp) stop=\(stopStamp) decision=\(String(describing: decision)) minimumKeyTime=\(String(format: "%.2f", minimumKeyTime)) hotkeyHasKey=\(hotkeyHasKey)"
    )

    guard decision == .proceedToTranscription else {
      // If the user recorded for less than minimumKeyTime and the hotkey is modifier-only,
      // discard the audio to avoid accidental triggers.
      transcriptionFeatureLogger.notice("Discarding short recording per decision \(String(describing: decision))")
      return .merge(
        .cancel(id: CancelID.contextRefresh),
        .run { _ in
          let url = await recording.stopRecording()
          guard !Task.isCancelled else { return }
          try? FileManager.default.removeItem(at: url)
        }
        .cancellable(id: CancelID.recordingCleanup, cancelInFlight: true)
      )
    }

    // Otherwise, proceed to transcription
    state.isTranscribing = true
    state.error = nil

    // Auto-switch model based on keyboard input source:
    // Hebrew keyboard → Caspi (Hebrew ASR), otherwise → selected model (Parakeet/Whisper)
    let (model, language) = Self.resolveModelAndLanguage(
      selectedModel: state.kolSettings.selectedModel,
      selectedLanguage: state.kolSettings.outputLanguage
    )
    state.resolvedLanguage = language

    state.isPrewarming = true
    let vadEnabled = state.kolSettings.vadSilenceDetectionEnabled
    let capturedVocabulary = state.capturedVocabulary

    return .merge(
      .cancel(id: CancelID.contextRefresh),
      .run { [sleepManagement] send in
        // Allow system to sleep again
        await sleepManagement.allowSleep()

        var audioURL: URL?
        do {
          let capturedURL = await recording.stopRecording()
          guard !Task.isCancelled else { return }
          audioURL = capturedURL

          // Create transcription options with the selected language
          // Note: cap concurrency to avoid audio I/O overloads on some Macs
          let decodeOptions = DecodingOptions(
            language: language,
            detectLanguage: language == nil, // Only auto-detect if no language specified
            chunkingStrategy: .vad,
          )

          let result = try await transcription.transcribe(capturedURL, model, decodeOptions, vadEnabled, capturedVocabulary) { _ in }

          transcriptionFeatureLogger.notice("Transcribed audio from \(capturedURL.lastPathComponent) to text length \(result.count)")
          await send(.transcriptionResult(result, capturedURL))
        } catch {
          transcriptionFeatureLogger.error("Transcription failed: \(error.localizedDescription)")
          await send(.transcriptionError(error, audioURL))
        }
      }
      .cancellable(id: CancelID.transcription)
    )
  }

  /// Checks the current macOS keyboard input source and routes to the appropriate model.
  /// Hebrew keyboard → Caspi + Hebrew language; otherwise → user's selected model + language.
  private static func resolveModelAndLanguage(
    selectedModel: String,
    selectedLanguage: String?
  ) -> (model: String, language: String?) {
    if isHebrewKeyboardActive() {
      transcriptionFeatureLogger.notice("Hebrew keyboard detected — using Caspi")
      return (QwenModel.caspiHebrew.identifier, "he")
    }
    // If Caspi is selected but keyboard is not Hebrew, use Parakeet for speed
    if QwenModel(rawValue: selectedModel) != nil {
      transcriptionFeatureLogger.notice("Non-Hebrew keyboard with Caspi selected — falling back to Parakeet")
      return (ParakeetModel.multilingualV3.identifier, selectedLanguage)
    }
    return (selectedModel, selectedLanguage)
  }

  private static func isHebrewKeyboardActive() -> Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
    guard let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
    let inputSourceID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
    return inputSourceID.lowercased().contains("hebrew")
  }
}

// MARK: - Transcription Handlers

private extension TranscriptionFeature {
  func handleTranscriptionResult(
    _ state: inout State,
    result: String,
    audioURL: URL
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false

    // Check for force quit command (emergency escape hatch)
    if ForceQuitCommandDetector.matches(result) {
      transcriptionFeatureLogger.fault("Force quit voice command recognized; terminating Kol.")
      return .run { _ in
        try? FileManager.default.removeItem(at: audioURL)
        await MainActor.run {
          NSApp.terminate(nil)
        }
      }
    }

    // If empty text, nothing else to do
    guard !result.isEmpty else {
      return .none
    }

    let duration = state.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

    transcriptionFeatureLogger.info("Raw transcription: '\(result)'")
    let remappings = state.kolSettings.wordRemappings
    let removalsEnabled = state.kolSettings.wordRemovalsEnabled
    let removals = state.kolSettings.wordRemovals
    let isRemappingScratchpadFocused = state.isRemappingScratchpadFocused
    let modifiedResult: String
    if isRemappingScratchpadFocused {
      modifiedResult = result
      transcriptionFeatureLogger.info("Scratchpad focused; skipping word modifications")
    } else {
      var output = result
      if removalsEnabled {
        let removedResult = WordRemovalApplier.apply(output, removals: removals)
        if removedResult != output {
          let enabledRemovalCount = removals.filter(\.isEnabled).count
          transcriptionFeatureLogger.info("Applied \(enabledRemovalCount) word removal(s)")
        }
        output = removedResult
      }
      // Word remappings are applied AFTER LLM post-processing (below)
      // so the LLM can't undo them.
      modifiedResult = output
    }

    guard !modifiedResult.isEmpty else {
      return .none
    }

    let sourceAppBundleID = state.sourceAppBundleID
    let sourceAppName = state.sourceAppName
    let transcriptionHistory = state.$transcriptionHistory
    let llmEnabled = state.kolSettings.llmPostProcessingEnabled
    let llmConfig = LLMProviderConfig(
      baseURL: state.kolSettings.llmProviderBaseURL,
      modelName: state.kolSettings.llmModelName
    )
    let llmCustomRules = state.kolSettings.llmCustomRules
    let llmPreset = state.kolSettings.llmProviderPreset
    let llmAppContextOverrides = AppContextOverrides(
      code: state.kolSettings.llmPromptCode,
      messaging: state.kolSettings.llmPromptMessaging,
      document: state.kolSettings.llmPromptDocument
    )
    let resolvedLanguage = state.resolvedLanguage
    let capturedScreenContext = state.capturedScreenContext
    let capturedCursorContext = state.capturedCursorContext
    let capturedVocabulary = state.capturedVocabulary
    let capturedIDEContext = state.capturedIDEContext

    return .run { [llmPostProcessing, keychain] send in
      do {
        var finalText = modifiedResult
        var llmMetadata: LLMMetadata?

        if llmEnabled {
          var apiKey = await keychain.load("llmApiKey_\(llmPreset)")
          if apiKey == nil {
            apiKey = await keychain.load("llmApiKey")
          }
          if let apiKey, !apiKey.isEmpty {
            let context = PostProcessingContext(
              text: finalText,
              inputLanguage: resolvedLanguage,
              sourceApp: sourceAppName ?? sourceAppBundleID,
              customRules: llmCustomRules.isEmpty ? nil : llmCustomRules,
              appContextOverrides: llmAppContextOverrides,
              ideContext: capturedIDEContext,
              screenContext: capturedScreenContext,
              structuredContext: capturedCursorContext,
              vocabularyHints: capturedVocabulary
            )
            do {
              let result = try await llmPostProcessing.process(context, llmConfig, apiKey)
              finalText = result.text
              // Only store metadata when LLM actually changed the text
              if result.text != modifiedResult {
                llmMetadata = result.metadata
              }
              transcriptionFeatureLogger.info("LLM post-processing took \(result.metadata.latencyMs ?? 0)ms")
            } catch {
              transcriptionFeatureLogger.error("LLM post-processing failed, using original: \(error.localizedDescription)")
            }
          } else {
            transcriptionFeatureLogger.notice("LLM enabled but no API key, skipping post-processing")
          }
        }

        // Apply word remappings after LLM so the LLM can't undo them
        if !isRemappingScratchpadFocused {
          let remappedText = WordRemappingApplier.apply(finalText, remappings: remappings)
          if remappedText != finalText {
            transcriptionFeatureLogger.info("Applied \(remappings.count) word remapping(s)")
            finalText = remappedText
          }
        }

        // Mechanical join: check character before cursor via AX API.
        // Works for text editors and messaging apps. Returns nil for terminals
        // (where AX doesn't expose cursor position), so no join is attempted.
        if let ch = screenContext.characterBeforeCursor() {
          if !ch.isWhitespace && !ch.isNewline {
            finalText = " " + finalText
          }
        }

        try await finalizeRecordingAndStoreTranscript(
          result: finalText,
          llmMetadata: llmMetadata,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL,
          transcriptionHistory: transcriptionHistory
        )
      } catch {
        await send(.transcriptionError(error, audioURL))
      }
    }
    .cancellable(id: CancelID.transcription)
  }

  func handleTranscriptionError(
    _ state: inout State,
    error: Error,
    audioURL: URL?
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false
    state.error = error.localizedDescription
    
    if let audioURL {
      try? FileManager.default.removeItem(at: audioURL)
    }

    return .none
  }

  /// Move file to permanent location, create a transcript record, paste text, and play sound.
  func finalizeRecordingAndStoreTranscript(
    result: String,
    llmMetadata: LLMMetadata?,
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?,
    audioURL: URL,
    transcriptionHistory: Shared<TranscriptionHistory>
  ) async throws {
    @Shared(.kolSettings) var kolSettings: KolSettings

    if kolSettings.saveTranscriptionHistory {
      let transcript = try await transcriptPersistence.save(
        result,
        llmMetadata,
        audioURL,
        duration,
        sourceAppBundleID,
        sourceAppName
      )

      transcriptionHistory.withLock { history in
        history.history.insert(transcript, at: 0)

        if let maxEntries = kolSettings.maxHistoryEntries, maxEntries > 0 {
          while history.history.count > maxEntries {
            if let removedTranscript = history.history.popLast() {
              Task {
                 try? await transcriptPersistence.deleteAudio(removedTranscript)
              }
            }
          }
        }
      }
    } else {
      try? FileManager.default.removeItem(at: audioURL)
    }

    await pasteboard.paste(result)
  }
}

// MARK: - Cancel/Discard Handlers

private extension TranscriptionFeature {
  func handleCancel(_ state: inout State) -> Effect<Action> {
    state.isTranscribing = false
    state.isRecording = false
    state.isPrewarming = false
    state.capturedScreenContext = nil
    state.capturedCursorContext = nil
    state.capturedVocabulary = nil
    state.capturedIDEContext = nil

    return .merge(
      .cancel(id: CancelID.transcription),
      .cancel(id: CancelID.contextRefresh),
      .run { [sleepManagement] _ in
        // Allow system to sleep again
        await sleepManagement.allowSleep()
        // Stop the recording to release microphone access
        let url = await recording.stopRecording()
        guard !Task.isCancelled else { return }
        try? FileManager.default.removeItem(at: url)
        soundEffect.play(.cancel)
      }
      .cancellable(id: CancelID.recordingCleanup, cancelInFlight: true)
    )
  }

  func handleDiscard(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    state.isPrewarming = false
    state.capturedScreenContext = nil
    state.capturedCursorContext = nil
    state.capturedVocabulary = nil
    state.capturedIDEContext = nil

    // Silently discard - no sound effect
    return .merge(
      .cancel(id: CancelID.contextRefresh),
      .run { [sleepManagement] _ in
        // Allow system to sleep again
        await sleepManagement.allowSleep()
        let url = await recording.stopRecording()
        guard !Task.isCancelled else { return }
        try? FileManager.default.removeItem(at: url)
      }
      .cancellable(id: CancelID.recordingCleanup, cancelInFlight: true)
    )
  }
}

// MARK: - Force Quit Command

private enum ForceQuitCommandDetector {
  static func matches(_ text: String) -> Bool {
    let normalized = normalize(text)
    return normalized == "force quit kol now" || normalized == "force quit kol"
      || normalized == "force quit hex now" || normalized == "force quit hex"
  }

  private static func normalize(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
