import ComposableArchitecture
import Foundation
import Testing

@testable import KolCore

@Suite @MainActor
struct TranscriptionContextPrivacyTests {
  private let audioURL = URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")

  private static func testDependencies(_ dependencies: inout DependencyValues) {
    dependencies.date.now = Date(timeIntervalSince1970: 100)
    dependencies.keychain = KeychainClient(save: { _, _ in }, load: { _ in nil }, delete: { _ in })
    dependencies.llmVocabulary = LLMVocabularyClient(extractNames: { _, _, _, _ in [] })
    dependencies.llmPostProcessing = LLMPostProcessingClient(process: { context, _, _ in
      LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
    })
    dependencies.recording.startRecording = { _ in .started }
    dependencies.recording.discardRecording = { _ in }
    dependencies.workspace.frontmostApplication = { nil }
    dependencies.screenContext.captureCursorContext = { _ in nil }
    dependencies.screenContext.captureVisibleText = { _ in nil }
    dependencies.windowContext.windowTitle = { _ in nil }
    dependencies.windowContext.browserURL = { _ in nil }
    dependencies.pasteboard.paste = { _, _ in }
  }

  private func settings(ai: Bool = true, screen: Bool = true) -> KolSettings {
    var settings = KolSettings()
    settings.llmPostProcessingEnabled = ai
    settings.llmScreenContextEnabled = screen
    settings.llmProviderBaseURL = "https://provider.example/v1"
    settings.llmModelName = "synthetic-model"
    settings.saveTranscriptionHistory = false
    settings.preventSystemSleep = false
    return settings
  }

  private func state(_ settings: KolSettings) -> TranscriptionFeature.State {
    let state = TranscriptionFeature.State(
      kolSettings: Shared(value: settings),
      modelBootstrapState: Shared(value: ModelBootstrapState()),
      transcriptionHistory: Shared(value: TranscriptionHistory())
    )
    state.$isRemappingScratchpadFocused = Shared(value: false)
    return state
  }

  private func completedCapture(_ settings: KolSettings) -> TranscriptionFeature.State {
    var state = state(settings)
    state.phase = .transcribing
    state.recordingDuration = 2
    state.sourceAppBundleID = "example.editor"
    state.sourceAppName = "Example Editor"
    state.capturedScreenContext = "use currentItem"
    state.capturedCursorContext = CursorContext(beforeCursor: "use currentItem", afterCursor: "", selectedText: nil, isTerminal: false)
    state.capturedVocabulary = ["currentItem"]
    state.capturedOCRVocabulary = ["ocrOnlyItem"]
    state.capturedIDEContext = IDEContext(openFileNames: ["Example.swift"])
    state.capturedConversationContext = ConversationContext(conversationName: "Open Source Weekly")
    state.$contextSession.withLock {
      $0 = TranscriptionFeature.ContextSession(
        id: UUID(), provider: TranscriptionFeature.ContextProvider(settings: settings), acceptingCaptures: false
      )
    }
    return state
  }

  @Test("Replacing screen capture with a context-disabled recording stops the old timer")
  func replacementStopsCaptureEffects() async throws {
    let clock = TestClock()
    let text = LockIsolated("firstItem")
    let keychainCancelled = LockIsolated(false)
    let store = TestStore(initialState: state(settings())) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.continuousClock = clock
      $0.screenContext.captureVisibleText = { _ in text.value }
      $0.keychain.load = { _ in
        do { try await clock.sleep(for: .seconds(10)) }
        catch { keychainCancelled.setValue(true) }
        return nil
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    #expect(store.state.capturedScreenContext == "firstItem")
    text.setValue("refreshedItem")
    await clock.advance(by: .seconds(1))
    await store.receive(\.contextRefreshed)
    #expect(store.state.capturedScreenContext == "refreshedItem")
    #expect(store.state.contextUpdateCount == 1)
    store.state.$kolSettings.withLock { $0.llmScreenContextEnabled = false }
    await store.send(.startRecording)
    await store.receive(\.recordingStarted)
    await store.finish()
    try await clock.checkSuspension()
    #expect(keychainCancelled.value == true)
    await clock.advance(by: .seconds(3))
    #expect(store.state.phase == .recording)
    #expect(store.state.capturedScreenContext == nil)
    #expect(store.state.contextUpdateCount == 0)
    store.state.$kolSettings.withLock { $0.llmScreenContextEnabled = true }
    store.dependencies.keychain.load = { _ in nil }
    text.setValue("currentItem")
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    #expect(store.state.capturedScreenContext == "currentItem")
    text.setValue("currentRefreshItem")
    await clock.advance(by: .seconds(1))
    await store.receive(\.contextRefreshed)
    #expect(store.state.capturedScreenContext == "currentRefreshItem")
    await store.send(.discard)
    await store.finish()
    try await clock.checkSuspension()
  }

  @Test("Refused and superseded startup stop their screen capture effects", arguments: [RecordingStartOutcome.failed(.unavailable), .superseded])
  func unsuccessfulStartupStopsCaptureEffects(_ outcome: RecordingStartOutcome) async throws {
    let clock = TestClock()
    let startup = ContextTestGate<RecordingStartOutcome>()
    let text = LockIsolated("startingItem")
    let keychainCancelled = LockIsolated(false)
    let store = TestStore(initialState: state(settings())) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.continuousClock = clock
      $0.recording.startRecording = { _ in await startup.wait() }
      $0.screenContext.captureVisibleText = { _ in text.value }
      $0.keychain.load = { _ in
        do { try await clock.sleep(for: .seconds(10)) }
        catch { keychainCancelled.setValue(true) }
        return nil
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    await startup.waitUntilRequested()
    #expect(store.state.capturedScreenContext == "startingItem")
    text.setValue("startingRefreshItem")
    await clock.advance(by: .seconds(1))
    await store.receive(\.contextRefreshed)
    #expect(store.state.capturedScreenContext == "startingRefreshItem")
    await startup.release(outcome)
    await store.receive(\.recordingStarted)
    await store.finish()
    try await clock.checkSuspension()
    #expect(keychainCancelled.value == true)
    await clock.advance(by: .seconds(3))
    #expect(store.state.phase == nil)
    #expect(store.state.contextSession == nil)
    #expect(store.state.capturedScreenContext == nil)
    store.dependencies.recording.startRecording = { _ in .started }
    store.dependencies.keychain.load = { _ in nil }
    text.setValue("currentItem")
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    #expect(store.state.capturedScreenContext == "currentItem")
    text.setValue("currentRefreshItem")
    await clock.advance(by: .seconds(1))
    await store.receive(\.contextRefreshed)
    #expect(store.state.capturedScreenContext == "currentRefreshItem")
    await store.send(.discard)
    await store.finish()
    try await clock.checkSuspension()
  }

  @Test("AI off keeps local vocabulary and makes no provider or keychain calls")
  func localContextWithoutAI() async {
    let vocabularyCalls = LockIsolated(0)
    let cleanupCalls = LockIsolated(0)
    let keychainCalls = LockIsolated(0)
    let asrVocabulary = LockIsolated<[String]?>(nil)
    let startTime = Date(timeIntervalSince1970: 100)
    let store = TestStore(initialState: state(settings(ai: false))) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.date.now = startTime
      $0.continuousClock = ContextTestClock()
      $0.screenContext.captureVisibleText = { _ in "use localItem in Example.swift" }
      $0.keychain.load = { _ in keychainCalls.withValue { $0 += 1 }; return "synthetic-key" }
      $0.llmVocabulary.extractNames = { _, _, _, _ in vocabularyCalls.withValue { $0 += 1 }; return [] }
      $0.llmPostProcessing.process = { context, _, _ in
        cleanupCalls.withValue { $0 += 1 }
        return LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
      $0.transcription.transcribe = { _, _, _, _, vocabulary, _ in
        asrVocabulary.setValue(vocabulary)
        return "use local item"
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    #expect(store.state.capturedVocabulary?.contains("localItem") == true)
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await store.receive(\.transcriptionResult)
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(asrVocabulary.value?.contains("localItem") == true)
    #expect(vocabularyCalls.value == 0)
    #expect(cleanupCalls.value == 0)
    #expect(keychainCalls.value == 0)
    #expect(store.state.capturedVocabulary == nil)
    #expect(store.state.contextSession == nil)
  }

  @Test("Starting another capture clears the previous app and rejects every old context action")
  func generationsAreIsolated() async throws {
    let keychain = ContextTestGate<String?>()
    let store = TestStore(initialState: state(settings())) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.continuousClock = ContextTestClock()
      $0.workspace.frontmostApplication = { FrontmostApp(bundleIdentifier: "example.first", localizedName: "Example First", processIdentifier: 42) }
      $0.screenContext.captureVisibleText = { _ in "oldAppItem" }
      $0.keychain.load = { _ in await keychain.wait() }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    await keychain.waitUntilRequested()
    let old = try #require(store.state.contextSession)
    store.state.$kolSettings.withLock { $0.llmScreenContextEnabled = false }
    store.dependencies.workspace.frontmostApplication = { nil }
    await store.send(.startRecording)
    let new = try #require(store.state.contextSession)
    #expect(old.id != new.id)
    #expect(store.state.sourceAppBundleID == nil)
    #expect(store.state.sourceAppName == nil)
    #expect(store.state.sourceAppPID == nil)
    #expect(store.state.capturedScreenContext == nil)
    #expect(store.state.capturedVocabulary == nil)
    await keychain.release("synthetic-key")
    await store.send(.recordingContextCaptured(generation: old.id, screenContext: "oldAppItem", cursorContext: nil, vocabulary: ["oldAppItem"], ideContext: nil, conversationContext: nil, ocrTriggered: true))
    await store.send(.contextRefreshed(generation: old.id, nil, "oldAppItem", ["oldAppItem"]))
    await store.send(.ocrCaptured(generation: old.id, vocabulary: ["oldOCRItem"]))
    await store.send(.vocabularyCaptured(generation: old.id, names: ["Carlos Mendes"], provider: old.provider, includesConversation: false))
    await store.send(.postProcessingFinished(generation: old.id))
    await store.send(.contextSessionFinished(generation: old.id))
    #expect(store.state.contextSession?.id == new.id)
    #expect(store.state.capturedScreenContext == nil)
    #expect(store.state.capturedVocabulary == nil)
    #expect(store.state.capturedOCRVocabulary == nil)
    #expect(store.state.capturedRemoteVocabulary == nil)
    await store.send(.discard)
    await store.finish()
  }

  @Test("Late ASR success and error cannot consume another recording's context", arguments: [false, true])
  func lateASRCompletion(_ fail: Bool) async throws {
    let asr = ContextTestGate<Bool>()
    let cleanupCalls = LockIsolated(0)
    let store = TestStore(initialState: state(settings(ai: false))) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.date.now = Date(timeIntervalSince1970: 100)
      $0.continuousClock = ContextTestClock()
      $0.screenContext.captureVisibleText = { _ in "firstItem" }
      $0.transcription.transcribe = { _, _, _, _, _, _ in
        if await asr.wait() { throw CancellationError() }
        return "old text"
      }
      $0.llmPostProcessing.process = { context, _, _ in
        cleanupCalls.withValue { $0 += 1 }
        return LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    let first = try #require(store.state.contextSession)
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await asr.waitUntilRequested()
    store.dependencies.screenContext.captureVisibleText = { _ in "secondItem" }
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    let second = try #require(store.state.contextSession)
    #expect(first.id != second.id)
    await asr.release(fail)
    await store.finish()
    #expect(store.state.contextSession?.id == second.id)
    #expect(store.state.contextSession?.acceptingCaptures == true)
    #expect(store.state.capturedScreenContext == "secondItem")
    #expect(store.state.capturedVocabulary == ["secondItem"])
    #expect(store.state.error == nil)
    #expect(cleanupCalls.value == 0)
    await store.send(.discard)
    await store.finish()
  }

  enum Revocation: CaseIterable, Sendable {
    case ai, screen, preset, baseURL, model

    func apply(to settings: inout KolSettings) {
      switch self {
      case .ai: settings.llmPostProcessingEnabled = false
      case .screen: settings.llmScreenContextEnabled = false
      case .preset: settings.llmProviderPreset = LLMProviderPreset.openrouter.rawValue
      case .baseURL: settings.llmProviderBaseURL = "https://other.example/v1"
      case .model: settings.llmModelName = "other-model"
      }
    }
  }

  @Test("Vocabulary dispatch rechecks consent and provider after keychain suspends", arguments: Revocation.allCases)
  func vocabularyDispatchRevocation(_ revocation: Revocation) async {
    let keychain = ContextTestGate<String?>()
    let calls = LockIsolated(0)
    let store = TestStore(initialState: state(settings())) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.continuousClock = ContextTestClock()
      $0.screenContext.captureVisibleText = { _ in "currentItem" }
      $0.keychain.load = { _ in await keychain.wait() }
      $0.llmVocabulary.extractNames = { _, _, _, _ in calls.withValue { $0 += 1 }; return [] }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    await keychain.waitUntilRequested()
    store.state.$kolSettings.withLock { revocation.apply(to: &$0) }
    await keychain.release("synthetic-key")
    await store.finish()
    #expect(calls.value == 0)
    await store.send(.discard)
    await store.finish()
  }

  @Test("Cleanup dispatch strips revoked fields after keychain suspends")
  func cleanupPerFieldRevocation() async {
    var settings = settings()
    settings.conversationContextEnabled = true
    settings.ocrContextEnabled = true
    settings.atMentionInsertionEnabled = true
    settings.llmCustomRules = "Prefer ExampleProduct."
    var initialState = completedCapture(settings)
    initialState.capturedRemoteVocabulary = ["conversationOnlyItem"]
    initialState.remoteVocabularyIncludesConversation = true
    let keychain = ContextTestGate<String?>()
    let requests = LockIsolated<[PostProcessingContext]>([])
    let store = TestStore(initialState: initialState) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.keychain.load = { _ in await keychain.wait() }
      $0.llmPostProcessing.process = { context, _, _ in
        requests.withValue { $0.append(context) }
        return LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
    }
    store.exhaustivity = .off
    await store.send(.transcriptionResult(generation: store.state.contextSession!.id, "use current item", audioURL, asrMs: 1))
    await keychain.waitUntilRequested()
    store.state.$kolSettings.withLock {
      $0.conversationContextEnabled = false
      $0.ocrContextEnabled = false
    }
    await keychain.release("synthetic-key")
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(requests.value.count == 1)
    #expect(requests.value.first?.screenContext == "use currentItem")
    #expect(requests.value.first?.vocabularyHints == ["currentItem", "Example.swift"])
    #expect(requests.value.first?.conversationContext == nil)
    #expect(requests.value.first?.atMentionEnabled == false)
    #expect(requests.value.first?.customRules == "Prefer ExampleProduct.")
  }

  @Test("Cleanup rechecks AI and provider after keychain suspends", arguments: [Revocation.ai, .preset, .baseURL, .model])
  func cleanupDispatchRevocation(_ revocation: Revocation) async {
    let keychain = ContextTestGate<String?>()
    let calls = LockIsolated(0)
    let store = TestStore(initialState: completedCapture(settings())) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.keychain.load = { _ in await keychain.wait() }
      $0.llmPostProcessing.process = { context, _, _ in
        calls.withValue { $0 += 1 }
        return LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
    }
    store.exhaustivity = .off
    await store.send(.transcriptionResult(generation: store.state.contextSession!.id, "use current item", audioURL, asrMs: 1))
    await keychain.waitUntilRequested()
    store.state.$kolSettings.withLock { revocation.apply(to: &$0) }
    await keychain.release("synthetic-key")
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(calls.value == 0)
  }

  @Test("Disabling screen context strips screen, IDE, OCR, and conversation while preserving explicit rules")
  func cleanupWithoutContext() async {
    var settings = settings()
    settings.llmCustomRules = "Prefer ExampleProduct."
    let requests = LockIsolated<[PostProcessingContext]>([])
    let store = TestStore(initialState: completedCapture(settings)) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.keychain.load = { _ in "synthetic-key" }
      $0.llmPostProcessing.process = { context, _, _ in
        requests.withValue { $0.append(context) }
        return LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
    }
    store.exhaustivity = .off
    store.state.$kolSettings.withLock { $0.llmScreenContextEnabled = false }
    await store.send(.transcriptionResult(generation: store.state.contextSession!.id, "use current item", audioURL, asrMs: 1))
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(requests.value.count == 1)
    #expect(requests.value.first?.screenContext == nil)
    #expect(requests.value.first?.structuredContext == nil)
    #expect(requests.value.first?.ideContext == nil)
    #expect(requests.value.first?.vocabularyHints == nil)
    #expect(requests.value.first?.conversationContext == nil)
    #expect(requests.value.first?.customRules == "Prefer ExampleProduct.")
    #expect(store.state.capturedScreenContext == nil)
  }

  @Test("A late OCR client response cannot update another generation")
  func lateOCRResponse() async throws {
    var settings = settings(ai: false)
    settings.ocrContextEnabled = true
    let ocr = ContextTestGate<String?>()
    let store = TestStore(initialState: state(settings)) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.continuousClock = ContextTestClock()
      $0.workspace.frontmostApplication = {
        FrontmostApp(bundleIdentifier: "example.first", localizedName: "Example First", processIdentifier: 42)
      }
      $0.ocrClient.captureWindowText = { _ in await ocr.wait() }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    await ocr.waitUntilRequested()
    let old = try #require(store.state.contextSession?.id)
    store.state.$kolSettings.withLock { $0.ocrContextEnabled = false }
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    let new = try #require(store.state.contextSession?.id)
    await ocr.release("oldOCRItem")
    await store.finish()
    #expect(old != new)
    #expect(store.state.capturedOCRVocabulary == nil)
    #expect(store.state.contextSession?.id == new)
    await store.send(.discard)
    await store.finish()
  }

  enum ResponseRevocation: CaseIterable, Sendable {
    case ai, screen, ocr, conversation, provider

    func apply(to settings: inout KolSettings) {
      switch self {
      case .ai: settings.llmPostProcessingEnabled = false
      case .screen: settings.llmScreenContextEnabled = false
      case .ocr: settings.ocrContextEnabled = false
      case .conversation: settings.conversationContextEnabled = false
      case .provider: settings.llmModelName = "other-model"
      }
    }
  }

  @Test("Revoking consent or provider during cleanup rejects transformed output", arguments: ResponseRevocation.allCases)
  func cleanupResponseRevocation(_ revocation: ResponseRevocation) async {
    var settings = settings()
    settings.conversationContextEnabled = true
    settings.ocrContextEnabled = true
    let response = ContextTestGate<String>()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: completedCapture(settings)) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.keychain.load = { _ in "synthetic-key" }
      $0.llmPostProcessing.process = { context, _, _ in
        LLMProcessingResult(text: await response.wait(), metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
      $0.pasteboard.paste = { text, isCurrent in
        try Task.checkCancellation()
        guard await isCurrent() else { throw CancellationError() }
        pasted.withValue { $0.append(text) }
      }
    }
    store.exhaustivity = .off
    await store.send(.transcriptionResult(generation: store.state.contextSession!.id, "original text", audioURL, asrMs: 1))
    await response.waitUntilRequested()
    store.state.$kolSettings.withLock { revocation.apply(to: &$0) }
    await response.release("transformed text")
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(pasted.value == ["original text"])
    #expect(store.state.isPostProcessing == false)
    #expect(store.state.contextSession == nil)
  }

  @Test("Starting another recording resets processing state while old cleanup is pending", arguments: [false, true])
  func pendingCleanupDoesNotKeepIndicator(_ discard: Bool) async throws {
    let response = ContextTestGate<String>()
    let pasted = LockIsolated<[String]>([])
    let initialState = completedCapture(settings())
    let store = TestStore(initialState: initialState) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.continuousClock = ContextTestClock()
      $0.keychain.load = { _ in "synthetic-key" }
      $0.llmPostProcessing.process = { context, _, _ in
        LLMProcessingResult(text: await response.wait(), metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
      $0.pasteboard.paste = { text, isCurrent in
        try Task.checkCancellation()
        guard await isCurrent() else { throw CancellationError() }
        pasted.withValue { $0.append(text) }
      }
    }
    store.exhaustivity = .off
    await store.send(.transcriptionResult(generation: store.state.contextSession!.id, "old text", audioURL, asrMs: 1))
    await response.waitUntilRequested()
    #expect(store.state.isPostProcessing)
    store.state.$kolSettings.withLock { $0.llmScreenContextEnabled = false }
    await store.send(.startRecording)
    #expect(!store.state.isPostProcessing)
    #expect(!store.state.isTranscribing)
    #expect(!store.state.isPrewarming)
    if discard {
      await store.send(.discard)
    } else {
      await store.send(.stopRecording)
    }
    await response.release("old transformed text")
    await store.finish()
    #expect(!store.state.isPostProcessing)
    #expect(!store.state.isTranscribing)
    #expect(!store.state.isPrewarming)
    #expect(store.state.contextSession == nil)
    #expect(pasted.value.isEmpty)
  }

  @Test("Refresh preserves IDE-only filenames in ASR vocabulary")
  func refreshRetainsIDEVocabulary() async throws {
    let asrVocabulary = LockIsolated<[String]?>(nil)
    let store = TestStore(initialState: state(settings(ai: false))) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.date.now = Date(timeIntervalSince1970: 100)
      $0.continuousClock = ContextTestClock()
      $0.workspace.frontmostApplication = {
        FrontmostApp(bundleIdentifier: "com.microsoft.VSCode", localizedName: "Example Editor", processIdentifier: 42)
      }
      $0.screenContext.captureVisibleText = { _ in "firstItem" }
      $0.ideContext.extractTabTitles = { _ in ["UnseenFile.swift"] }
      $0.transcription.transcribe = { _, _, _, _, vocabulary, _ in
        asrVocabulary.setValue(vocabulary)
        return "use second item"
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingContextCaptured)
    let generation = try #require(store.state.contextSession?.id)
    await store.send(.contextRefreshed(generation: generation, nil, "secondItem", ["secondItem"]))
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(asrVocabulary.value == ["secondItem", "UnseenFile.swift"])
  }

  @Test("Authorized current-session context reaches cleanup")
  func authorizedContext() async {
    var settings = settings()
    settings.conversationContextEnabled = true
    settings.ocrContextEnabled = true
    settings.atMentionInsertionEnabled = true
    let requests = LockIsolated<[PostProcessingContext]>([])
    let store = TestStore(initialState: completedCapture(settings)) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0)
      $0.recording.stopRecording = { _ in .audio(URL(fileURLWithPath: "/tmp/kol-synthetic-context-test.wav")) }
      $0.keychain.load = { _ in "synthetic-key" }
      $0.llmPostProcessing.process = { context, _, _ in
        requests.withValue { $0.append(context) }
        return LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
    }
    store.exhaustivity = .off
    await store.send(.transcriptionResult(generation: store.state.contextSession!.id, "use current item", audioURL, asrMs: 1))
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(requests.value.count == 1)
    #expect(requests.value.first?.screenContext == "use currentItem")
    #expect(requests.value.first?.structuredContext?.beforeCursor == "use currentItem")
    #expect(requests.value.first?.ideContext?.openFileNames == ["Example.swift"])
    #expect(requests.value.first?.vocabularyHints == ["currentItem", "Example.swift", "ocrOnlyItem"])
    #expect(requests.value.first?.conversationContext?.conversationName == "Open Source Weekly")
    #expect(requests.value.first?.atMentionEnabled == true)
  }
}

private actor ContextTestGate<Value: Sendable> {
  private var continuation: CheckedContinuation<Value, Never>?
  private var requestWaiter: CheckedContinuation<Void, Never>?
  private var requested = false

  func wait() async -> Value {
    await withCheckedContinuation {
      continuation = $0
      requested = true
      requestWaiter?.resume()
      requestWaiter = nil
    }
  }

  func waitUntilRequested() async {
    guard !requested else { return }
    await withCheckedContinuation { requestWaiter = $0 }
  }

  func release(_ value: Value) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}

private struct ContextTestClock: Clock {
  var now: ContinuousClock.Instant { ContinuousClock().now }
  var minimumResolution: Duration { .nanoseconds(1) }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
    throw CancellationError()
  }
}
