//
//  TranscriptionFeature.swift
//  Kol
//
//  Created by Kit Langton on 1/24/25.
//

import ComposableArchitecture
import Foundation

private let transcriptionFeatureLogger = KolLog.transcription

private let maxVocabularyHints = 30
private let ocrQualityThreshold = 50

@Reducer
public struct TranscriptionFeature {
  public init() {}

  @ObservableState
  public struct State: Equatable {
    public init() {}
    public var didStartTask: Bool = false
    public var isRecording: Bool = false
    public var isTranscribing: Bool = false
    public var isPostProcessing: Bool = false
    public var isPrewarming: Bool = false
    public var error: String?
    public var recordingStartTime: Date?
    public var meter: Meter = .init(averagePower: 0, peakPower: 0)
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var sourceAppPID: pid_t?
    public var resolvedLanguage: String?
    public var capturedScreenContext: String?
    public var capturedCursorContext: CursorContext?
    public var capturedVocabulary: [String]?
    public var capturedIDEContext: IDEContext?
    public var capturedConversationContext: ConversationContext?
    public var resolvedAppCategory: AppContextCategory?
    public var contextUpdateCount: Int = 0
    public var editTrackingActive: Bool = false
    public var editTrackingBaselineText: String?
    public var editTrackingElementHash: Int?
    public var editTrackingTranscriptID: UUID?
    public var editTrackingPollCount: Int = 0
    public var ocrTriggered: Bool = false
    public var lastOCRTickNumber: Int = 0
    @Shared(.kolSettings) public var kolSettings: KolSettings
    @Shared(.isRemappingScratchpadFocused) public var isRemappingScratchpadFocused: Bool = false
    @Shared(.modelBootstrapState) public var modelBootstrapState: ModelBootstrapState
    @Shared(.transcriptionHistory) public var transcriptionHistory: TranscriptionHistory
  }

  public enum Action {
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

    // Initial context capture (async, dispatched from startRecording)
    case recordingContextCaptured(
      screenContext: String?,
      cursorContext: CursorContext?,
      vocabulary: [String]?,
      ideContext: IDEContext?,
      conversationContext: ConversationContext?,
      ocrTriggered: Bool
    )

    // Post-processing state
    case postProcessingStarted
    case postProcessingFinished

    // OCR fallback for Electron/Chromium apps
    case ocrCaptured(String, [String]?)

    // Edit tracking
    case editTrackingStarted(baselineText: String, elementHash: Int, transcriptID: UUID)
    case editTrackingTick
    case editTrackingResult(String?)
    case editTrackingStop

    // Model availability
    case modelMissing
  }

  public enum CancelID {
    case metering
    case recordingCleanup
    case transcription
    case contextRefresh
    case initialContextCapture
    case ocrCapture
    case editTracking
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
  @Dependency(\.windowContext) var windowContext
  @Dependency(\.nameCache) var nameCache
  @Dependency(\.editTracking) var editTrackingClient
  @Dependency(\.ocrClient) var ocrClient
  @Dependency(\.workspace) var workspace
  @Dependency(\.inputSource) var inputSource
  @Dependency(\.continuousClock) var clock

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Guard against double-fire (.task can arrive from both AppFeature and SwiftUI .task modifier)
        guard !state.didStartTask else { return .none }
        state.didStartTask = true
        // Starts three concurrent effects:
        // 1) Observing audio meter (long-lived, runs for app lifetime)
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

      // MARK: - Edit Tracking

      case let .editTrackingStarted(baselineText, elementHash, transcriptID):
        state.editTrackingActive = true
        state.editTrackingBaselineText = baselineText
        state.editTrackingElementHash = elementHash
        state.editTrackingTranscriptID = transcriptID
        state.editTrackingPollCount = 0
        // Start 500ms polling timer
        return .run { send in
          while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))
            await send(.editTrackingTick)
          }
        }
        .cancellable(id: CancelID.editTracking, cancelInFlight: true)

      case .editTrackingTick:
        guard state.editTrackingActive, let hash = state.editTrackingElementHash else { return .none }
        state.editTrackingPollCount += 1
        // Max 20 polls (10 seconds at 500ms)
        if state.editTrackingPollCount >= 20 {
          return .send(.editTrackingStop)
        }
        return .run { [editTrackingClient] send in
          let text = await MainActor.run {
            editTrackingClient.readText(hash)
          }
          await send(.editTrackingResult(text))
        }

      case let .editTrackingResult(text):
        guard state.editTrackingActive else { return .none }
        if text == nil {
          // Element changed or can't be read — stop tracking
          return .send(.editTrackingStop)
        }
        return .none

      case .editTrackingStop:
        guard state.editTrackingActive,
              let baselineText = state.editTrackingBaselineText,
              let transcriptID = state.editTrackingTranscriptID,
              let hash = state.editTrackingElementHash
        else {
          state.editTrackingActive = false
          return .cancel(id: CancelID.editTracking)
        }
        state.editTrackingActive = false
        let transcriptionHistory = state.$transcriptionHistory
        return .merge(
          .cancel(id: CancelID.editTracking),
          .run { [editTrackingClient] _ in
            // Read final text
            let finalText = await MainActor.run {
              editTrackingClient.readText(hash)
            }
            guard let finalText, finalText != baselineText else { return }

            let (vector, edits) = EditVectorComputer.compute(original: baselineText, edited: finalText)
            guard !vector.isEmpty, vector.contains(where: { $0 != "M" }) else { return }

            transcriptionFeatureLogger.info("Edit vector: \(vector) (\(edits.filter { $0.operation != .match }.count) change(s))")

            // Update transcript in history
            transcriptionHistory.withLock { history in
              if let idx = history.history.firstIndex(where: { $0.id == transcriptID }) {
                history.history[idx].editVector = vector
                history.history[idx].wordEdits = edits
              }
            }
          }
        )

      // MARK: - Context Refresh During Recording

      case .contextRefreshTick:
        guard state.isRecording else { return .none }
        let bundleID = state.sourceAppBundleID
        let sourceAppPID = state.sourceAppPID

        // OCR cooldown: skip OCR on ticks that are too close to the last OCR run.
        // The context refresh timer fires every 1s; a cooldown of 3 ticks means OCR
        // runs at most every ~3s, saving ~170ms of CPU + memory per skipped tick.
        let ocrCooldownTicks = 3
        let ticksSinceLastOCR = state.contextUpdateCount - state.lastOCRTickNumber
        let shouldOCR = state.ocrTriggered && ticksSinceLastOCR >= ocrCooldownTicks

        return .run { [screenContext, vocabularyCache, ocrClient] send in
          let cursor = await MainActor.run {
            screenContext.captureCursorContext(bundleID)
          }
          let flatText: String?
          if let cursorText = cursor?.flatText {
            flatText = cursorText
          } else if !PromptLayers.isTerminal(bundleID) {
            flatText = await MainActor.run {
              screenContext.captureVisibleText(bundleID)
            }
          } else {
            flatText = nil
          }

          // If OCR was triggered and AX text is still sparse, re-run OCR
          if shouldOCR, (flatText?.count ?? 0) < ocrQualityThreshold, let pid = sourceAppPID {
            if let ocrText = await ocrClient.captureWindowText(pid) {
              let vocab = VocabularyExtractor.extract(from: ocrText)
              vocabularyCache.merge(vocab)
              let terms = vocabularyCache.topTerms(maxVocabularyHints)
              await send(.ocrCaptured(ocrText, terms))
              return
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

      case let .ocrCaptured(_, vocabulary):
        // OCR text feeds vocabulary extraction only — proper nouns and identifiers
        // are cached in VocabularyCacheClient and persist across recordings.
        // Raw OCR text is not used for LLM screen context.
        if let vocabulary {
          state.capturedVocabulary = vocabulary
        }
        state.lastOCRTickNumber = state.contextUpdateCount
        state.contextUpdateCount += 1
        return .none

      case let .recordingContextCaptured(screenContext, cursorContext, vocabulary, ide, conversation, ocrTriggered):
        guard state.isRecording else { return .none }
        state.capturedScreenContext = screenContext
        state.capturedCursorContext = cursorContext
        state.capturedVocabulary = vocabulary
        state.capturedIDEContext = ide
        state.capturedConversationContext = conversation
        if ocrTriggered {
          state.ocrTriggered = true
          let axTextCount = screenContext?.count ?? 0
          transcriptionFeatureLogger.info("OCR triggered: AX text \(axTextCount) chars < \(ocrQualityThreshold) threshold")
        }
        return .none

      case .postProcessingStarted:
        state.isPostProcessing = true
        return .none

      case .postProcessingFinished:
        state.isPostProcessing = false
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
    // DO NOT capture [recording] — TCA propagates dependencies through the task context.
    // Explicit capture resolves the dependency at effect creation time, which gets the
    // default (non-live) value whose observeAudioLevel returns an empty stream.
    // DO NOT add cancelInFlight — it kills the metering stream and breaks the waveform.
    // DO NOT cancel this effect in stop/cancel/discard — it's a long-lived subscription
    // started once in .task that runs for the app's lifetime.
    .run { send in
      for await meter in await recording.observeAudioLevel() {
        await send(.audioLevelUpdated(meter))
      }
    }
    .cancellable(id: CancelID.metering)
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
    
    // Capture the active application (PID stored for OCR/AX effects during recording)
    if let activeApp = workspace.frontmostApplication() {
      state.sourceAppBundleID = activeApp.bundleIdentifier
      state.sourceAppName = activeApp.localizedName
      state.sourceAppPID = activeApp.processIdentifier
    }

    // Resolve app category synchronously (cheap NSWorkspace call).
    // AX tree walks are deferred to an async effect below to avoid
    // blocking recording start by 50-200ms on Electron apps.
    if let pid = workspace.frontmostApplication()?.processIdentifier {
      let windowTitle = windowContext.windowTitle(pid)
      let knownCategory = PromptLayers.appContextCategory(for: state.sourceAppBundleID)
      let url: String? = knownCategory == nil ? windowContext.browserURL(pid) : nil
      state.resolvedAppCategory = AppContextResolver.resolve(
        bundleID: state.sourceAppBundleID,
        appName: state.sourceAppName,
        url: url,
        windowTitle: windowTitle
      )
    } else {
      state.resolvedAppCategory = nil
    }

    // Stop any in-progress edit tracking from a previous recording
    if state.editTrackingActive {
      state.editTrackingActive = false
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

    // Async initial context capture — AX tree walks run off the main reducer path.
    let bundleID = state.sourceAppBundleID
    let resolvedCategory = state.resolvedAppCategory
    let llmEnabled = state.kolSettings.llmPostProcessingEnabled
    let screenContextEnabled = state.kolSettings.llmScreenContextEnabled
    let conversationEnabled = state.kolSettings.conversationContextEnabled
    let ocrEnabled = state.kolSettings.ocrContextEnabled
    let pid = state.sourceAppPID
    let appName = state.sourceAppName

    let initialContextEffect: Effect<Action> = llmEnabled && screenContextEnabled
      ? .run { [screenContext, vocabularyCache, ideContext, windowContext, nameCache] send in
          // Screen context: cursor context preferred, flat text fallback
          let cursor: CursorContext? = await MainActor.run { screenContext.captureCursorContext(bundleID) }
          let flatText: String?
          if let cursorText = cursor?.flatText {
            flatText = cursorText
          } else if !PromptLayers.isTerminal(bundleID) {
            flatText = await MainActor.run { screenContext.captureVisibleText(bundleID) }
          } else {
            flatText = nil
          }

          // Vocabulary extraction
          var vocabulary: [String]?
          if let text = flatText, !text.isEmpty {
            let vocab = VocabularyExtractor.extract(from: text)
            vocabularyCache.merge(vocab)
            vocabulary = vocabularyCache.topTerms(maxVocabularyHints)
          }

          // IDE context (code editors only)
          var ide: IDEContext?
          if PromptLayers.appContextCategory(for: bundleID) == .code,
             let p = pid {
            let tabTitles = await MainActor.run { ideContext.extractTabTitles(p) }
            if !tabTitles.isEmpty {
              ide = IDEContext(openFileNames: tabTitles)
              let fileVocab = VocabularyExtractor.Result(properNouns: [], identifiers: [], fileNames: tabTitles)
              vocabularyCache.merge(fileVocab)
              vocabulary = vocabularyCache.topTerms(maxVocabularyHints)
            }
          }

          // Conversation context (messaging/email)
          var conversation: ConversationContext?
          if conversationEnabled,
             let p = pid,
             let category = resolvedCategory,
             category == .messaging || category == .email {
            let windowTitle = await MainActor.run { windowContext.windowTitle(p) }
            let conversationName = ConversationContext.conversationName(fromWindowTitle: windowTitle)
            let participants = await MainActor.run { windowContext.messagingParticipants(p) }
            let conversationID = conversationName ?? windowTitle ?? "unknown"
            let bid = bundleID ?? "unknown"
            if !participants.isEmpty {
              nameCache.merge(participants, bid, conversationID)
            }
            let cachedNames = nameCache.allNames(bid, 30)
            let allParticipants = Array(Set(participants + cachedNames))
            conversation = ConversationContext(
              conversationName: conversationName,
              participants: allParticipants,
              bundleID: bundleID
            )
            if !allParticipants.isEmpty {
              let nameVocab = VocabularyExtractor.Result(properNouns: allParticipants, identifiers: [], fileNames: [])
              vocabularyCache.merge(nameVocab)
              vocabulary = vocabularyCache.topTerms(maxVocabularyHints)
            }
          }

          // OCR quality gate: trigger OCR if AX text is too sparse
          let shouldTriggerOCR = ocrEnabled && (flatText?.count ?? 0) < ocrQualityThreshold && pid != nil

          await send(.recordingContextCaptured(
            screenContext: flatText,
            cursorContext: cursor,
            vocabulary: vocabulary,
            ideContext: ide,
            conversationContext: conversation,
            ocrTriggered: shouldTriggerOCR
          ))

          // Fire OCR capture immediately if triggered
          if shouldTriggerOCR, let p = pid {
            if let ocrText = await ocrClient.captureWindowText(p) {
              let vocab = VocabularyExtractor.extract(from: ocrText)
              vocabularyCache.merge(vocab)
              let terms = vocabularyCache.topTerms(maxVocabularyHints)
              await send(.ocrCaptured(ocrText, terms))
            }
          }
        }
        .cancellable(id: CancelID.initialContextCapture, cancelInFlight: true)
      : .none

    // Start periodic context refresh during recording (1s interval)
    let shouldRefreshContext = llmEnabled && screenContextEnabled
    let contextRefreshEffect: Effect<Action> = shouldRefreshContext
      ? .run { [clock] send in
          for await _ in clock.timer(interval: .seconds(1)) {
            await send(.contextRefreshTick)
          }
        }
        .cancellable(id: CancelID.contextRefresh, cancelInFlight: true)
      : .none

    return .merge(startRecordingEffect, initialContextEffect, contextRefreshEffect)
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
        .cancel(id: CancelID.ocrCapture),
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
    let (model, language) = resolveModelAndLanguage(
      selectedModel: state.kolSettings.selectedModel,
      selectedLanguage: state.kolSettings.outputLanguage
    )
    state.resolvedLanguage = language

    state.isPrewarming = true
    let vadEnabled = state.kolSettings.vadSilenceDetectionEnabled
    // Use vocabulary from cache — includes OCR-extracted terms from this and previous recordings
    let capturedVocabulary = state.capturedVocabulary

    return .merge(
      .cancel(id: CancelID.contextRefresh),
      .cancel(id: CancelID.ocrCapture),
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
          let options = TranscriptionOptions(
            language: language,
            detectLanguage: language == nil,
            useVADChunking: true
          )

          let result = try await transcription.transcribe(capturedURL, model, options, vadEnabled, capturedVocabulary) { _ in }

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
  private func resolveModelAndLanguage(
    selectedModel: String,
    selectedLanguage: String?
  ) -> (model: String, language: String?) {
    if inputSource.isHebrewKeyboardActive() {
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
        exit(0)
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

    // Set post-processing state synchronously so the indicator stays visible
    // with no gap between transcribing → postProcessing.
    if llmEnabled {
      state.isPostProcessing = true
    }
    let llmConfig = LLMProviderConfig(
      baseURL: state.kolSettings.llmProviderBaseURL,
      modelName: state.kolSettings.llmModelName
    )
    let llmCustomRules = state.kolSettings.llmCustomRules
    let llmPreset = state.kolSettings.llmProviderPreset
    let llmAppContextOverrides = AppContextOverrides(
      code: state.kolSettings.llmPromptCode,
      messaging: state.kolSettings.llmPromptMessaging,
      document: state.kolSettings.llmPromptDocument,
      email: state.kolSettings.llmPromptEmail
    )
    let resolvedLanguage = state.resolvedLanguage
    let capturedScreenContext = state.capturedScreenContext
    let capturedCursorContext = state.capturedCursorContext
    // Read vocabulary fresh from the cache — OCR terms may have been merged since recording started.
    // Always include the source app name so the LLM can resolve ASR mishearings of it.
    var capturedVocabulary = vocabularyCache.topTerms(maxVocabularyHints)
    if let appName = state.sourceAppName, !appName.isEmpty,
       !(capturedVocabulary ?? []).contains(appName) {
      capturedVocabulary = (capturedVocabulary ?? []) + [appName]
    }
    let capturedIDEContext = state.capturedIDEContext
    let capturedConversationContext = state.capturedConversationContext
    let resolvedAppCategory = state.resolvedAppCategory
    let atMentionEnabled = state.kolSettings.atMentionInsertionEnabled
      && state.kolSettings.conversationContextEnabled
    let editTrackingEnabled = state.kolSettings.editTrackingEnabled

    return .run { [llmPostProcessing, keychain, nameCache, editTrackingClient] send in
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
              vocabularyHints: capturedVocabulary,
              conversationContext: capturedConversationContext,
              resolvedCategory: resolvedAppCategory
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
            await send(.postProcessingFinished)
          } else {
            transcriptionFeatureLogger.notice("LLM enabled but no API key, skipping post-processing")
            await send(.postProcessingFinished)
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

        // @-mention rewriting: "at Alice" → "@Alice" for known participants
        if atMentionEnabled, let convo = capturedConversationContext, !convo.participants.isEmpty {
          let rewritten = AtMentionRewriter.rewrite(finalText, knownNames: convo.participants)
          if rewritten != finalText {
            transcriptionFeatureLogger.info("Applied @-mention rewriting")
            finalText = rewritten
          }
        }

        let transcriptID = try await finalizeRecordingAndStoreTranscript(
          result: finalText,
          llmMetadata: llmMetadata,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL,
          transcriptionHistory: transcriptionHistory
        )

        // Start edit tracking after paste if enabled
        if editTrackingEnabled, let transcriptID {
          if let snapshot = await MainActor.run(body: { editTrackingClient.captureSnapshot() }) {
            transcriptionFeatureLogger.info("Starting edit tracking for transcript \(transcriptID)")
            await send(.editTrackingStarted(baselineText: snapshot.text, elementHash: snapshot.hash, transcriptID: transcriptID))
          }
        }
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
    state.isPostProcessing = false
    state.isPrewarming = false
    state.error = error.localizedDescription

    if let audioURL {
      try? FileManager.default.removeItem(at: audioURL)
    }

    return .none
  }

  /// Move file to permanent location, create a transcript record, paste text, and play sound.
  /// Returns the transcript ID (or nil if history saving is disabled).
  @discardableResult
  func finalizeRecordingAndStoreTranscript(
    result: String,
    llmMetadata: LLMMetadata?,
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?,
    audioURL: URL,
    transcriptionHistory: Shared<TranscriptionHistory>
  ) async throws -> UUID? {
    @Shared(.kolSettings) var kolSettings: KolSettings
    var transcriptID: UUID?

    if kolSettings.saveTranscriptionHistory {
      let transcript = try await transcriptPersistence.save(
        result,
        llmMetadata,
        audioURL,
        duration,
        sourceAppBundleID,
        sourceAppName
      )
      transcriptID = transcript.id

      var removedTranscripts: [Transcript] = []
      transcriptionHistory.withLock { history in
        history.history.insert(transcript, at: 0)

        if let maxEntries = kolSettings.maxHistoryEntries, maxEntries > 0 {
          while history.history.count > maxEntries {
            if let removedTranscript = history.history.popLast() {
              removedTranscripts.append(removedTranscript)
            }
          }
        }
      }
      for transcript in removedTranscripts {
        try? await transcriptPersistence.deleteAudio(transcript)
      }
    } else {
      try? FileManager.default.removeItem(at: audioURL)
    }

    await pasteboard.paste(result)
    return transcriptID
  }
}

// MARK: - Cancel/Discard Handlers

private extension TranscriptionFeature {
  func handleCancel(_ state: inout State) -> Effect<Action> {
    state.isTranscribing = false
    state.isRecording = false
    state.isPostProcessing = false
    state.isPrewarming = false
    state.capturedScreenContext = nil
    state.capturedCursorContext = nil
    state.capturedVocabulary = nil
    state.capturedIDEContext = nil
    state.capturedConversationContext = nil
    state.resolvedAppCategory = nil
    state.ocrTriggered = false
    state.lastOCRTickNumber = 0

    return .merge(
      .cancel(id: CancelID.transcription),
      .cancel(id: CancelID.contextRefresh),
      .cancel(id: CancelID.initialContextCapture),
      .cancel(id: CancelID.ocrCapture),
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
    state.capturedConversationContext = nil
    state.resolvedAppCategory = nil
    state.ocrTriggered = false
    state.lastOCRTickNumber = 0

    // Silently discard - no sound effect
    return .merge(
      .cancel(id: CancelID.contextRefresh),
      .cancel(id: CancelID.ocrCapture),
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
