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
private let axTimeoutSeconds: Double = 2.0

/// Runs a closure on MainActor with a timeout. Returns nil if the deadline expires,
/// preventing hung Accessibility API calls from blocking the main thread indefinitely.
private func withMainActorTimeout<T: Sendable>(
  seconds: Double = axTimeoutSeconds,
  body: @escaping @MainActor @Sendable () -> T
) async -> T? {
  await withTaskGroup(of: T?.self) { group in
    group.addTask { await MainActor.run { body() } }
    group.addTask {
      try? await Task.sleep(for: .seconds(seconds))
      return nil
    }
    let first = await group.next()!
    group.cancelAll()
    return first
  }
}

@Reducer
public struct TranscriptionFeature {
  public init() {}

  @ObservableState
  public struct State: Equatable {
    public init(
      kolSettings: Shared<KolSettings> = Shared(.kolSettings),
      modelBootstrapState: Shared<ModelBootstrapState> = Shared(.modelBootstrapState),
      transcriptionHistory: Shared<TranscriptionHistory> = Shared(.transcriptionHistory)
    ) {
      self._kolSettings = kolSettings
      self._modelBootstrapState = modelBootstrapState
      self._transcriptionHistory = transcriptionHistory
    }
    public var didStartTask: Bool = false
    public var phase: Phase?
    public var recordingDuration: TimeInterval = 0
    public var isRecording: Bool {
      switch phase { case .acquiring, .recording: true; default: false }
    }
    public var isTranscribing: Bool { phase == .stopping || phase == .transcribing }
    public var isPostProcessing: Bool { phase == .processing || phase == .archiving || phase == .inserting }
    public var isPrewarming: Bool { phase == .stopping || phase == .transcribing }
    public var error: String?
    public var recordingStartTime: Date?
    public var meter: Meter = .init(averagePower: 0, peakPower: 0)
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var sourceAppPID: pid_t?
    public var resolvedLanguage: String?
    public var capturedFocusedText: FocusedText?
    public var capturedVocabulary: [String]?
    public var capturedIDEContext: IDEContext?
    public var capturedConversationContext: ConversationContext?
    public var resolvedAppCategory: AppContextCategory?
    public var capturedOCRVocabulary: [String]?
    public var capturedRemoteVocabulary: [String]?
    public var remoteVocabularyIncludesConversation: Bool = false
    @Shared(value: nil) public var contextSession: ContextSession?
    @Shared public var kolSettings: KolSettings
    @Shared(.isRemappingScratchpadFocused) public var isRemappingScratchpadFocused: Bool = false
    @Shared public var modelBootstrapState: ModelBootstrapState
    @Shared public var transcriptionHistory: TranscriptionHistory
  }

  public enum Phase: Equatable, Sendable {
    case acquiring(stopRequested: Bool)
    case recording
    case stopping
    case transcribing
    case processing
    case archiving
    case inserting
  }

  public struct ContextProvider: Equatable, Sendable {
    public let preset: String
    public let config: LLMProviderConfig

    init(settings: KolSettings) {
      preset = settings.llmProviderPreset
      config = LLMProviderConfig(baseURL: settings.llmProviderBaseURL, modelName: settings.llmModelName)
    }
  }

  public struct ContextSession: Equatable, Sendable {
    public let id: UUID
    public let provider: ContextProvider
    public var acceptingCaptures: Bool
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
    case recordingStarted(generation: UUID, RecordingStartOutcome)
    case recordingStopped(generation: UUID, RecordingStopOutcome)
    case archived(generation: UUID, Transcript)
    case insertionReady(generation: UUID, String)

    // Cancel/discard flow
    case cancel
    case discard  // Too short or accidental recording

    // Transcription result flow
    case transcriptionResult(generation: UUID, String, URL, asrMs: Int)
    case transcriptionError(generation: UUID, Error, URL?)

    // Context refresh during recording
    case contextRefreshTick(generation: UUID)
    case contextRefreshed(generation: UUID, textSource: TextSourceSnapshot?)

    // Initial context capture (async, dispatched from startRecording)
    case recordingContextCaptured(
      generation: UUID,
      textSource: TextSourceSnapshot?,
      ideContext: IDEContext?,
      conversationContext: ConversationContext?
    )

    // Post-processing state
    case postProcessingFinished(generation: UUID)
    case contextSessionFinished(generation: UUID)

    // Local OCR vocabulary
    case ocrCaptured(generation: UUID, vocabulary: [String])
    case vocabularyCaptured(generation: UUID, names: [String], provider: ContextProvider, includesConversation: Bool)

    // Model availability
    case modelMissing
  }

  public enum CancelID: Hashable {
    case metering
    case contextRefresh(UUID)
    case initialContextCapture(UUID)
    case refreshCapture(UUID)
    case ocrCapture(UUID)
    case session(UUID)
  }

  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.date.now) var now
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.llmPostProcessing) var llmPostProcessing
  @Dependency(\.keychain) var keychain
  @Dependency(\.screenContext) var screenContext
  @Dependency(\.ideContext) var ideContext
  @Dependency(\.windowContext) var windowContext
  @Dependency(\.llmVocabulary) var llmVocabulary
  @Dependency(\.ocrClient) var ocrClient
  @Dependency(\.workspace) var workspace
  @Dependency(\.continuousClock) var clock

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Guard against double-fire (.task can arrive from both AppFeature and SwiftUI .task modifier)
        guard !state.didStartTask else { return .none }
        state.didStartTask = true
        let selectedModel = state.kolSettings.selectedModel
        // Starts four concurrent effects:
        // 1) Observing audio meter (long-lived, runs for app lifetime)
        // 2) Monitoring hot key events
        // 3) Priming the recorder for instant startup
        // 4) Preloading ASR model (Parakeet + CTC vocabulary boosting)
        return .merge(
          startMeteringEffect(),
          startHotKeyMonitoringEffect(),
          warmUpRecorderEffect(),
          preloadModelEffect(model: selectedModel)
        )

      // MARK: - Metering

      case let .audioLevelUpdated(meter):
        state.meter = meter
        return .none

      // MARK: - HotKey Flow

      case .hotKeyPressed:
        return .send(.startRecording)

      case .hotKeyReleased:
        // If we're currently recording, then stop. Otherwise, just cancel
        // the delayed "startRecording" effect if we never actually started.
        return handleHotKeyReleased(isRecording: state.isRecording)

      // MARK: - Recording Flow

      case .startRecording:
        return handleStartRecording(&state)

      case .stopRecording:
        return handleStopRecording(&state)

      case let .recordingStarted(generation, outcome):
        guard state.contextSession?.id == generation,
              case let .acquiring(stopRequested) = state.phase else {
          return .run { _ in await recording.discardRecording(generation) }
        }
        switch outcome {
        case .started:
          state.phase = .recording
          return stopRequested ? beginStop(&state, generation: generation) : .none
        case .superseded:
          retireContext(&state)
          return cancelCaptures(generation)
        case let .failed(error):
          return handleTranscriptionError(&state, error: error, audioURL: nil)
        }

      case let .recordingStopped(generation, outcome):
        guard state.contextSession?.id == generation, state.phase == .stopping else {
          if case let .audio(url) = outcome { return removeAudio(url) }
          return .none
        }
        switch outcome {
        case let .audio(url):
          state.phase = .transcribing
          return transcribeAudio(&state, generation: generation, url: url)
        case .stale:
          retireContext(&state)
          return cancelCaptures(generation)
        case let .failed(error):
          return handleTranscriptionError(&state, error: error, audioURL: nil)
        }

      case let .archived(generation, transcript):
        guard state.contextSession?.id == generation, state.phase == .archiving else {
          return .run { _ in try? await transcriptPersistence.deleteAudio(transcript) }
        }
        var removed: [Transcript] = []
        let historyLimit = state.kolSettings.maxHistoryEntries
        state.$transcriptionHistory.withLock { history in
          history.history.insert(transcript, at: 0)
          if let limit = historyLimit, limit > 0 {
            while history.history.count > limit {
              removed.append(history.history.removeLast())
            }
          }
        }
        state.phase = .inserting
        let removedTranscripts = removed
        return .merge(
          insertText(&state, generation: generation, text: transcript.text),
          .run { _ in await transcriptPersistence.deleteAudioFiles(for: removedTranscripts) }
        )

      case let .insertionReady(generation, text):
        guard state.contextSession?.id == generation, state.phase == .archiving else { return .none }
        state.phase = .inserting
        return insertText(&state, generation: generation, text: text)

      // MARK: - Transcription Results

      case let .transcriptionResult(generation, result, audioURL, asrMs):
        guard state.contextSession?.id == generation, state.phase == .transcribing else { return removeAudio(audioURL) }
        return handleTranscriptionResult(&state, result: result, audioURL: audioURL, asrMs: asrMs)

      case let .transcriptionError(generation, error, audioURL):
        guard state.contextSession?.id == generation else {
          return audioURL.map(removeAudio) ?? .none
        }
        return handleTranscriptionError(&state, error: error, audioURL: audioURL)

      case .modelMissing:
        return .none

      // MARK: - Context Refresh During Recording

      case let .contextRefreshTick(generation):
        guard acceptsContext(state, generation: generation) else {
          if state.isRecording, state.contextSession?.id == generation { clearCapturedContext(&state) }
          return .none
        }
        let bundleID = state.sourceAppBundleID
        let sourceAppPID = state.sourceAppPID
        let settings = state.$kolSettings
        let session = state.$contextSession
        return .run { [screenContext] send in
          guard Self.acceptsContext(session, settings, generation: generation) else { return }
          let sourceApplication = sourceAppPID.map {
            FrontmostApp(bundleIdentifier: bundleID, localizedName: nil, processIdentifier: $0)
          }
          let snapshot = PromptLayers.isTerminal(bundleID)
            ? nil : await withMainActorTimeout { screenContext.capture(sourceApplication) } ?? nil
          guard Self.acceptsContext(session, settings, generation: generation) else { return }
          await send(.contextRefreshed(generation: generation, textSource: snapshot))
        }
        .cancellable(id: CancelID.refreshCapture(generation), cancelInFlight: true)
        .cancellable(id: CancelID.session(generation))

      case let .contextRefreshed(generation, snapshot):
        guard acceptsContext(state, generation: generation) else { return .none }
        let vocabulary = Self.contextTerms(snapshot?.vocabularyTerms ?? [])
        guard snapshot?.focused != state.capturedFocusedText || vocabulary != state.capturedVocabulary else { return .none }
        state.capturedFocusedText = snapshot?.focused
        state.capturedVocabulary = vocabulary
        return .none

      case let .ocrCaptured(generation, vocabulary):
        guard acceptsContext(state, generation: generation), state.kolSettings.ocrContextEnabled else { return .none }
        state.capturedOCRVocabulary = vocabulary
        return .none

      case let .vocabularyCaptured(generation, names, provider, includesConversation):
        guard acceptsContext(state, generation: generation),
              state.kolSettings.llmPostProcessingEnabled,
              provider == ContextProvider(settings: state.kolSettings),
              !includesConversation || state.kolSettings.conversationContextEnabled else { return .none }
        state.capturedRemoteVocabulary = Self.contextTerms(names)
        state.remoteVocabularyIncludesConversation = includesConversation
        return .none

      case let .recordingContextCaptured(generation, snapshot, ide, conversation):
        guard acceptsContext(state, generation: generation) else { return .none }
        state.capturedFocusedText = snapshot?.focused
        state.capturedVocabulary = Self.contextTerms(snapshot?.vocabularyTerms ?? [])
        state.capturedIDEContext = ide
        state.capturedConversationContext = state.kolSettings.conversationContextEnabled ? conversation : nil
        return .none

      case let .postProcessingFinished(generation):
        guard state.contextSession?.id == generation else { return .none }
        state.phase = .archiving
        return .none

      case let .contextSessionFinished(generation):
        guard state.contextSession?.id == generation else { return .none }
        retireContext(&state)
        return cancelCaptures(generation)

      // MARK: - Cancel/Discard Flow

      case .cancel:
        guard state.phase != nil else {
          return .none
        }
        return endSession(&state)

      case .discard:
        // Silent discard for quick/accidental recordings
        guard state.isRecording else {
          return .none
        }
        return endSession(&state)
      }
    }
  }
}

private extension TranscriptionFeature {
  static func contextTerms(_ terms: [String]) -> [String]? {
    var seen = Set<String>()
    let result = terms.filter { seen.insert($0.lowercased()).inserted }
    return result.isEmpty ? nil : Array(result.prefix(maxVocabularyHints))
  }

  static func prioritizedContextTerms(
    focused: FocusedText?, ocr: [String]?, window: [String]?, ide: [String]?, remote: [String]?
  ) -> [String]? {
    contextTerms((focused.map { VocabularyExtractor.extract(from: $0.plainText).allTerms } ?? [])
      + (ocr ?? []) + (window ?? []) + (ide ?? []) + (remote ?? []))
  }

  static func acceptsContext(
    _ session: Shared<ContextSession?>,
    _ settings: Shared<KolSettings>,
    generation: UUID
  ) -> Bool {
    session.wrappedValue?.id == generation && session.wrappedValue?.acceptingCaptures == true
      && settings.wrappedValue.llmScreenContextEnabled
      && session.wrappedValue?.provider == ContextProvider(settings: settings.wrappedValue)
      && !Task.isCancelled
  }

  func acceptsContext(_ state: State, generation: UUID) -> Bool {
    state.isRecording && Self.acceptsContext(state.$contextSession, state.$kolSettings, generation: generation)
  }

  func clearCapturedContext(_ state: inout State) {
    state.capturedFocusedText = nil
    state.capturedVocabulary = nil
    state.capturedOCRVocabulary = nil
    state.capturedRemoteVocabulary = nil
    state.remoteVocabularyIncludesConversation = false
    state.capturedIDEContext = nil
    state.capturedConversationContext = nil
  }

  func retireContext(_ state: inout State) {
    state.phase = nil
    state.$contextSession.withLock { $0 = nil }
    clearCapturedContext(&state)
    state.sourceAppBundleID = nil
    state.sourceAppName = nil
    state.sourceAppPID = nil
    state.resolvedAppCategory = nil
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

  func preloadModelEffect(model: String) -> Effect<Action> {
    .run { _ in
      do {
        try await transcription.downloadModel(model) { _ in }
        transcriptionFeatureLogger.info("ASR model preloaded at launch: \(model)")
      } catch {
        transcriptionFeatureLogger.error("ASR model preload failed: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - HotKey Press/Release Handlers

private extension TranscriptionFeature {
  func handleHotKeyReleased(isRecording: Bool) -> Effect<Action> {
    // Always stop recording when hotkey is released
    return isRecording ? .send(.stopRecording) : .none
  }
}

// MARK: - Recording Handlers

private extension TranscriptionFeature {
  func handleStartRecording(_ state: inout State) -> Effect<Action> {
    guard state.modelBootstrapState.isModelReady else {
      return .send(.modelMissing)
    }
    let previous = state.contextSession?.id
    retireContext(&state)
    let contextSession = ContextSession(id: UUID(), provider: ContextProvider(settings: state.kolSettings), acceptingCaptures: true)
    state.$contextSession.withLock { $0 = contextSession }
    state.phase = .acquiring(stopRequested: false)
    let startTime = now
    state.recordingStartTime = startTime
    
    // Capture the active application (PID stored for OCR/AX effects during recording)
    let activeApp = workspace.frontmostApplication()
    state.sourceAppBundleID = activeApp?.bundleIdentifier
    state.sourceAppName = activeApp?.localizedName
    state.sourceAppPID = activeApp?.processIdentifier

    // Resolve app category synchronously (cheap NSWorkspace call).
    // AX tree walks are deferred to an async effect below to avoid
    // blocking recording start by 50-200ms on Electron apps.
    if let pid = activeApp?.processIdentifier {
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

    transcriptionFeatureLogger.notice("Recording started at \(startTime.ISO8601Format())")

    let session = state.$contextSession
    let startRecordingEffect: Effect<Action> = .merge(
      previous.map { id in
        .merge(
          .cancel(id: CancelID.session(id)),
          cancelCaptures(id),
          .run { _ in await recording.discardRecording(id) }
        )
      } ?? .none,
      .run { @MainActor send in
        guard session.wrappedValue?.id == contextSession.id, !Task.isCancelled else { return }
        let outcome = await recording.startRecording(contextSession.id)
        guard session.wrappedValue?.id == contextSession.id, !Task.isCancelled else {
          await recording.discardRecording(contextSession.id)
          return
        }
        send(.recordingStarted(generation: contextSession.id, outcome))
      }
      .cancellable(id: CancelID.session(contextSession.id))
    )

    // Async initial context capture — AX tree walks run off the main reducer path.
    let bundleID = state.sourceAppBundleID
    let resolvedCategory = state.resolvedAppCategory
    let screenContextEnabled = state.kolSettings.llmScreenContextEnabled
    let pid = state.sourceAppPID
    let settings = state.$kolSettings
    let generation = contextSession.id
    let provider = contextSession.provider

    let initialContextEffect: Effect<Action> = screenContextEnabled
      ? .run { [screenContext, ideContext, windowContext, keychain, llmVocabulary, workspace] send in
          guard Self.acceptsContext(session, settings, generation: generation) else { return }
          transcriptionFeatureLogger.debug("Initial context capture started for pid \(pid ?? 0)")
          let snapshot = PromptLayers.isTerminal(bundleID)
            ? nil : await withMainActorTimeout { screenContext.capture(activeApp) } ?? nil
          guard Self.acceptsContext(session, settings, generation: generation) else { return }
          let vocabText = snapshot?.vocabularySourceText
          var ide: IDEContext?
          if PromptLayers.appContextCategory(for: bundleID) == .code, let pid {
            let titles = await withMainActorTimeout { ideContext.extractTabTitles(pid) } ?? []
            if !titles.isEmpty {
              ide = IDEContext(openFileNames: titles)
            }
          }
          var conversation: ConversationContext?
          if settings.wrappedValue.conversationContextEnabled, let pid,
             resolvedCategory == .messaging || resolvedCategory == .email {
            let title = await withMainActorTimeout { windowContext.windowTitle(pid) } ?? nil
            conversation = ConversationContext(conversationName: ConversationContext.conversationName(fromWindowTitle: title))
          }
          guard Self.acceptsContext(session, settings, generation: generation) else { return }
          await send(.recordingContextCaptured(
            generation: generation,
            textSource: snapshot,
            ideContext: ide,
            conversationContext: conversation
          ))
          guard let text = vocabText, !text.isEmpty,
                Self.acceptsContext(session, settings, generation: generation),
                settings.wrappedValue.llmPostProcessingEnabled,
                !provider.config.isLocal else { return }
          let apiKey = await keychain.loadLLMAPIKey(for: provider.preset)
          guard Self.acceptsContext(session, settings, generation: generation),
                settings.wrappedValue.llmPostProcessingEnabled,
                provider == ContextProvider(settings: settings.wrappedValue),
                let pid, workspace.frontmostApplication()?.processIdentifier == pid,
                let apiKey, !apiKey.isEmpty else { return }
          let conversationID = settings.wrappedValue.conversationContextEnabled ? conversation?.conversationName : nil
          do {
            let names = try await llmVocabulary.extractNames(text, conversationID, provider.config, apiKey)
            await send(.vocabularyCaptured(generation: generation, names: names, provider: provider, includesConversation: conversationID != nil))
          } catch {
            // Local extraction remains available when the provider fails.
          }
        }
        .cancellable(id: CancelID.initialContextCapture(generation), cancelInFlight: true)
        .cancellable(id: CancelID.session(generation))
      : .none

    // Start periodic context refresh during recording (1s interval)
    let shouldRefreshContext = screenContextEnabled
    let contextRefreshEffect: Effect<Action> = shouldRefreshContext
      ? .run { [clock] send in
          guard Self.acceptsContext(session, settings, generation: generation) else { return }
          for await _ in clock.timer(interval: .seconds(1)) {
            guard Self.acceptsContext(session, settings, generation: generation) else { return }
            await send(.contextRefreshTick(generation: generation))
          }
        }
        .cancellable(id: CancelID.contextRefresh(generation), cancelInFlight: true)
        .cancellable(id: CancelID.session(generation))
      : .none

    let ocrEffect: Effect<Action> = screenContextEnabled && state.kolSettings.ocrContextEnabled && pid != nil
      ? .run { [ocrClient, clock, workspace] send in
          guard let pid else { return }
          while Self.acceptsContext(session, settings, generation: generation),
                settings.wrappedValue.ocrContextEnabled {
            if workspace.frontmostApplication()?.processIdentifier == pid,
               let vocabulary = await ocrClient.captureWindowVocabulary(pid),
               Self.acceptsContext(session, settings, generation: generation),
               settings.wrappedValue.ocrContextEnabled,
               workspace.frontmostApplication()?.processIdentifier == pid {
              await send(.ocrCaptured(generation: generation, vocabulary: vocabulary))
            }
            try await clock.sleep(for: .seconds(3))
          }
        }
        .cancellable(id: CancelID.ocrCapture(generation), cancelInFlight: true)
        .cancellable(id: CancelID.session(generation))
      : .none

    return .merge(startRecordingEffect, initialContextEffect, contextRefreshEffect, ocrEffect)
  }

  func handleStopRecording(_ state: inout State) -> Effect<Action> {
    guard state.isRecording, state.phase != .acquiring(stopRequested: true),
          let generation = state.contextSession?.id else { return .none }
    transcriptionFeatureLogger.debug("Recording stop requested")
    state.$contextSession.withLock { $0?.acceptingCaptures = false }
    if let pid = state.sourceAppPID, workspace.frontmostApplication()?.processIdentifier != pid {
      clearCapturedContext(&state)
    }
    state.recordingDuration = state.recordingStartTime.map { now.timeIntervalSince($0) } ?? 0
    let decision = RecordingDecisionEngine.decide(
      .init(
        hotkey: state.kolSettings.hotkey,
        minimumKeyTime: state.kolSettings.minimumKeyTime,
        recordingStartTime: state.recordingStartTime,
        currentTime: now
      )
    )
    guard decision == .proceedToTranscription else { return endSession(&state) }
    if case .acquiring = state.phase {
      state.phase = .acquiring(stopRequested: true)
      return cancelCaptures(generation)
    }
    return beginStop(&state, generation: generation)
  }

  func beginStop(_ state: inout State, generation: UUID) -> Effect<Action> {
    state.phase = .stopping
    state.error = nil
    return .merge(
      cancelCaptures(generation),
      .run { @MainActor send in
        let outcome = await recording.stopRecording(generation)
        guard !Task.isCancelled else {
          if case let .audio(url) = outcome { try? FileManager.default.removeItem(at: url) }
          return
        }
        send(.recordingStopped(generation: generation, outcome))
      }
      .cancellable(id: CancelID.session(generation))
    )
  }

  func transcribeAudio(_ state: inout State, generation: UUID, url: URL) -> Effect<Action> {
    let model = state.kolSettings.selectedModel
    let language = state.kolSettings.outputLanguage
    state.resolvedLanguage = language
    let vadEnabled = state.kolSettings.vadSilenceDetectionEnabled
    let vocabulary = state.kolSettings.llmScreenContextEnabled
      && state.contextSession?.provider == ContextProvider(settings: state.kolSettings)
      ? Self.prioritizedContextTerms(
          focused: state.capturedFocusedText,
          ocr: state.kolSettings.ocrContextEnabled ? state.capturedOCRVocabulary : nil,
          window: state.capturedVocabulary,
          ide: state.capturedIDEContext?.openFileNames,
          remote: state.kolSettings.llmPostProcessingEnabled
            && (!state.remoteVocabularyIncludesConversation || state.kolSettings.conversationContextEnabled)
            ? state.capturedRemoteVocabulary : nil
        )
      : nil
    return .run { @MainActor send in
      do {
        let options = TranscriptionOptions(language: language, detectLanguage: language == nil, useVADChunking: true)
        let start = Date()
        let text = try await transcription.transcribe(url, model, options, vadEnabled, vocabulary) { _ in }
        guard !Task.isCancelled else {
          try? FileManager.default.removeItem(at: url)
          return
        }
        send(.transcriptionResult(generation: generation, text, url, asrMs: Int(Date().timeIntervalSince(start) * 1000)))
      } catch {
        guard !Task.isCancelled else {
          try? FileManager.default.removeItem(at: url)
          return
        }
        send(.transcriptionError(generation: generation, error, url))
      }
    }
    .cancellable(id: CancelID.session(generation))
  }

  func cancelCaptures(_ generation: UUID) -> Effect<Action> {
    .merge(
      .cancel(id: CancelID.contextRefresh(generation)),
      .cancel(id: CancelID.refreshCapture(generation)),
      .cancel(id: CancelID.ocrCapture(generation)),
      .cancel(id: CancelID.initialContextCapture(generation))
    )
  }

  func removeAudio(_ url: URL) -> Effect<Action> {
    .run { _ in try? FileManager.default.removeItem(at: url) }
  }

}

// MARK: - Transcription Handlers

private extension TranscriptionFeature {
  func handleTranscriptionResult(
    _ state: inout State,
    result: String,
    audioURL: URL,
    asrMs: Int
  ) -> Effect<Action> {
    state.phase = .processing
    state.$contextSession.withLock { $0?.acceptingCaptures = false }

    // Check for force quit command (emergency escape hatch)
    if ForceQuitCommandDetector.matches(result) {
      transcriptionFeatureLogger.fault("Force quit voice command recognized; terminating Kol.")
      return .run { _ in
        try? FileManager.default.removeItem(at: audioURL)
        exit(0)
      }
    }

    // If empty text, nothing else to do
    guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      let generation = state.contextSession?.id
      retireContext(&state)
      return .merge(generation.map(cancelCaptures) ?? .none, removeAudio(audioURL))
    }

    let duration = state.recordingDuration

    transcriptionFeatureLogger.info("Raw transcription: '\(result, privacy: .private)'")

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
      if state.kolSettings.removeFillerWords {
        output = FillerWordCleanup.apply(output)
      }
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

    guard !modifiedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      let generation = state.contextSession?.id
      retireContext(&state)
      return .merge(generation.map(cancelCaptures) ?? .none, removeAudio(audioURL))
    }

    let sourceAppBundleID = state.sourceAppBundleID
    let sourceAppPID = state.sourceAppPID
    let sourceAppName = state.sourceAppName
    let llmEnabled = state.kolSettings.llmPostProcessingEnabled

    let settings = state.$kolSettings
    let session = state.$contextSession
    let generation = state.contextSession?.id ?? UUID()
    let provider = ContextProvider(settings: state.kolSettings)
    let capturedProvider = state.contextSession?.provider
    let resolvedLanguage = state.resolvedLanguage
    let capturedFocusedText = state.capturedFocusedText
    let capturedVocabulary = state.capturedVocabulary
    let capturedOCRVocabulary = state.capturedOCRVocabulary
    let capturedRemoteVocabulary = state.capturedRemoteVocabulary
    let remoteVocabularyIncludesConversation = state.remoteVocabularyIncludesConversation
    let capturedIDEContext = state.capturedIDEContext
    let capturedConversationContext = state.capturedConversationContext
    let resolvedAppCategory = state.resolvedAppCategory
    return .run { @MainActor [llmPostProcessing, keychain] send in
      do {
        var finalText = modifiedResult
        var llmMetadata: LLMMetadata?

        if llmEnabled, settings.wrappedValue.llmPostProcessingEnabled {
          let apiKey = provider.config.isLocal ? nil : await keychain.loadLLMAPIKey(for: provider.preset)
          let liveSettings = settings.wrappedValue
          if session.wrappedValue?.id == generation,
             liveSettings.llmPostProcessingEnabled,
             provider == ContextProvider(settings: liveSettings),
             provider.config.isLocal || !(apiKey ?? "").isEmpty {
            let targetMatches = sourceAppPID.map { workspace.frontmostApplication()?.processIdentifier == $0 } ?? false
            let contextAllowed = targetMatches && liveSettings.llmScreenContextEnabled && capturedProvider == provider
            let conversationAllowed = contextAllowed && liveSettings.conversationContextEnabled
            let ocrAllowed = contextAllowed && liveSettings.ocrContextEnabled
            let vocabulary = contextAllowed
              ? Self.prioritizedContextTerms(
                  focused: capturedFocusedText,
                  ocr: ocrAllowed ? capturedOCRVocabulary : nil,
                  window: capturedVocabulary,
                  ide: capturedIDEContext?.openFileNames,
                  remote: !remoteVocabularyIncludesConversation || conversationAllowed ? capturedRemoteVocabulary : nil
                )
              : nil
            let overrides = AppContextOverrides(
              code: liveSettings.llmPromptCode,
              messaging: liveSettings.llmPromptMessaging,
              document: liveSettings.llmPromptDocument,
              email: liveSettings.llmPromptEmail
            )
            let context = PostProcessingContext(
              text: finalText,
              inputLanguage: resolvedLanguage,
              sourceApp: sourceAppName ?? sourceAppBundleID,
              customRules: liveSettings.llmCustomRules.isEmpty ? nil : liveSettings.llmCustomRules,
              appContextOverrides: overrides,
              ideContext: contextAllowed ? capturedIDEContext : nil,
              focusedText: contextAllowed ? capturedFocusedText : nil,
              vocabularyHints: vocabulary,
              conversationContext: conversationAllowed ? capturedConversationContext : nil,
              resolvedCategory: resolvedAppCategory,
              atMentionEnabled: conversationAllowed && liveSettings.atMentionInsertionEnabled
            )
            do {
              let result = try await llmPostProcessing.process(context, provider.config, apiKey ?? "")
              let currentSettings = settings.wrappedValue
              let consentStillValid = (!contextAllowed || currentSettings.llmScreenContextEnabled)
                && (!conversationAllowed || currentSettings.conversationContextEnabled)
                && (!ocrAllowed || currentSettings.ocrContextEnabled)
                && (!contextAllowed || workspace.frontmostApplication()?.processIdentifier == sourceAppPID)
              if session.wrappedValue?.id == generation,
                 currentSettings.llmPostProcessingEnabled,
                 provider == ContextProvider(settings: currentSettings), consentStillValid {
                finalText = SpokenDottedNumberFormatter.apply(result.text)
                llmMetadata = result.metadata
                transcriptionFeatureLogger.info("LLM output: '\(result.text, privacy: .private)' (\(result.metadata.latencyMs ?? 0)ms)")
              }
            } catch {
              transcriptionFeatureLogger.error("LLM post-processing failed, using original: \(error.localizedDescription)")
            }
          }
        }
        send(.postProcessingFinished(generation: generation))
        guard session.wrappedValue?.id == generation, !Task.isCancelled else {
          try? FileManager.default.removeItem(at: audioURL)
          return
        }

        // Apply word remappings after LLM so the LLM can't undo them
        if !isRemappingScratchpadFocused {
          let remappedText = WordRemappingApplier.apply(finalText, remappings: remappings)
          if remappedText != finalText {
            transcriptionFeatureLogger.info("Applied \(remappings.count) word remapping(s)")
            finalText = remappedText
          }
        }

        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          try? FileManager.default.removeItem(at: audioURL)
          send(.contextSessionFinished(generation: generation))
          return
        }

        let llmMs = llmMetadata?.latencyMs
        let totalMs = asrMs + (llmMs ?? 0)
        let timing = PipelineTiming(
          asrMs: asrMs,
          llmMs: llmMs,
          totalMs: totalMs
        )
        if settings.wrappedValue.saveTranscriptionHistory {
          let transcript = try await transcriptPersistence.save(
            finalText, llmMetadata, audioURL, duration, sourceAppBundleID, sourceAppName, timing
          )
          guard session.wrappedValue?.id == generation, !Task.isCancelled else {
            try? await transcriptPersistence.deleteAudio(transcript)
            return
          }
          send(.archived(generation: generation, transcript))
        } else {
          try? FileManager.default.removeItem(at: audioURL)
          guard session.wrappedValue?.id == generation, !Task.isCancelled else { return }
          send(.insertionReady(generation: generation, finalText))
        }

      } catch {
        if session.wrappedValue?.id == generation, !Task.isCancelled {
          send(.transcriptionError(generation: generation, error, audioURL))
        } else {
          try? FileManager.default.removeItem(at: audioURL)
        }
      }
    }
    .cancellable(id: CancelID.session(generation))
  }

  func handleTranscriptionError(
    _ state: inout State,
    error: Error,
    audioURL: URL?
  ) -> Effect<Action> {
    let generation = state.contextSession?.id
    state.error = error.localizedDescription
    retireContext(&state)

    if let audioURL {
      try? FileManager.default.removeItem(at: audioURL)
    }

    return generation.map(cancelCaptures) ?? .none
  }

  func insertText(_ state: inout State, generation: UUID, text: String) -> Effect<Action> {
    let session = state.$contextSession
    return .run { send in
      let started = Date()
      do {
        try await pasteboard.paste(text) { session.wrappedValue?.id == generation && !Task.isCancelled }
        transcriptionFeatureLogger.debug("Insertion completed in \(Int(Date().timeIntervalSince(started) * 1000))ms")
      } catch {
        transcriptionFeatureLogger.error("Insertion ended: \(error.localizedDescription)")
      }
      await send(.contextSessionFinished(generation: generation))
    }
    .cancellable(id: CancelID.session(generation))
  }

}

// MARK: - Cancel/Discard Handlers

private extension TranscriptionFeature {
  func endSession(_ state: inout State) -> Effect<Action> {
    let generation = state.contextSession?.id
    retireContext(&state)
    return .merge(
      generation.map(cancelCaptures) ?? .none,
      generation.map { id in
        .merge(
          .cancel(id: CancelID.session(id)),
          .run { _ in
            await recording.discardRecording(id)
          }
        )
      } ?? .none
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
