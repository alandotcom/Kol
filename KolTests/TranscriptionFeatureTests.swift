import AppKit
import ComposableArchitecture
import Foundation
import Testing

@testable import Kol
@testable import KolCore

/// TranscriptionFeature TCA TestStore tests.
///
/// Currently disabled: TestStore crashes when running inside the host app (TEST_HOST)
/// because the app's @main entry point initializes a live TCA Store that conflicts
/// with TestStore's dependency injection. Fix: guard app init with
/// `ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil` check.
@Suite(.serialized, .disabled("TestStore crashes in host-app context — needs app init guard"))
@MainActor
struct TranscriptionFeatureTests {

  // MARK: - Helpers

  private static func makeState() -> TranscriptionFeature.State {
    @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
    $modelBootstrapState.withLock { $0 = .init(isModelReady: true) }
    return TranscriptionFeature.State()
  }

  private static func makeStore(
    now: Date = Date(timeIntervalSince1970: 1_000),
    configure: (inout DependencyValues) -> Void = { _ in }
  ) -> TestStore<TranscriptionFeature.State, TranscriptionFeature.Action> {
    let store = TestStore(initialState: makeState()) {
      TranscriptionFeature()
    } withDependencies: {
      $0.date.now = now
      // Minimal mocks to prevent crashes
      $0.recording.startRecording = {}
      $0.recording.stopRecording = { URL(fileURLWithPath: "/tmp/test.wav") }
      $0.sleepManagement.preventSleep = { _ in }
      $0.sleepManagement.allowSleep = {}
      $0.soundEffects.play = { _ in }
      $0.screenContext.captureVisibleText = { _ in nil }
      $0.screenContext.captureCursorContext = { _ in nil }
      $0.screenContext.characterBeforeCursor = { nil }
      $0.windowContext.windowTitle = { _ in nil }
      $0.windowContext.browserURL = { _ in nil }
      $0.windowContext.messagingParticipants = { _ in [] }
      $0.ideContext.extractTabTitles = { _ in [] }
      configure(&$0)
    }
    store.exhaustivity = .off
    return store
  }

  // MARK: - Recording State Transitions

  @Test("startRecording sets isRecording and captures source app")
  func startRecordingSetsState() async {
    let now = Date(timeIntervalSince1970: 1_000)
    let activeApp = NSWorkspace.shared.frontmostApplication
    let store = Self.makeStore(now: now)

    await store.send(.startRecording) {
      $0.isRecording = true
      $0.recordingStartTime = now
      $0.sourceAppBundleID = activeApp?.bundleIdentifier
      $0.sourceAppName = activeApp?.localizedName
      $0.sourceAppPID = activeApp?.processIdentifier
    }
  }

  @Test("startRecording with model not ready sends modelMissing")
  func startRecordingModelNotReady() async {
    @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
    $modelBootstrapState.withLock { $0 = .init(isModelReady: false) }

    let store = TestStore(initialState: TranscriptionFeature.State()) {
      TranscriptionFeature()
    } withDependencies: {
      $0.soundEffects.play = { _ in }
    }
    store.exhaustivity = .off

    await store.send(.startRecording)
    await store.receive(\.modelMissing)
  }

  // MARK: - Cancel Flow

  @Test("Cancel resets all recording state")
  func cancelResetsState() async {
    let store = Self.makeStore()

    await store.send(.startRecording) {
      $0.isRecording = true
    }
    await store.send(.cancel) {
      $0.isRecording = false
      $0.isTranscribing = false
      $0.isPostProcessing = false
      $0.isPrewarming = false
      $0.capturedScreenContext = nil
      $0.capturedCursorContext = nil
      $0.capturedVocabulary = nil
      $0.capturedIDEContext = nil
      $0.capturedConversationContext = nil
      $0.resolvedAppCategory = nil
      $0.ocrTriggered = false
      $0.lastOCRTickNumber = 0
    }
  }

  // MARK: - Discard Flow

  @Test("Discard resets recording state silently")
  func discardResetsState() async {
    let store = Self.makeStore()

    await store.send(.startRecording) {
      $0.isRecording = true
    }
    await store.send(.discard) {
      $0.isRecording = false
      $0.isPrewarming = false
      $0.capturedScreenContext = nil
      $0.capturedCursorContext = nil
      $0.capturedVocabulary = nil
      $0.capturedIDEContext = nil
      $0.capturedConversationContext = nil
      $0.resolvedAppCategory = nil
      $0.ocrTriggered = false
      $0.lastOCRTickNumber = 0
    }
  }

  // MARK: - Transcription Error

  @Test("Transcription error clears transcribing state")
  func transcriptionErrorClearsState() async {
    let store = Self.makeStore()

    // Simulate being in transcribing state
    await store.send(.startRecording) {
      $0.isRecording = true
    }

    let error = NSError(domain: "test", code: 1)
    let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
    await store.send(.transcriptionError(error, audioURL)) {
      $0.isTranscribing = false
      $0.isPostProcessing = false
      $0.isPrewarming = false
      $0.error = error.localizedDescription
    }
  }

  // MARK: - Post-Processing State

  @Test("Post-processing state set when LLM enabled")
  func postProcessingStateSetWhenLLMEnabled() async {
    // Enable LLM before creating the store via @Shared
    @Shared(.kolSettings) var kolSettings: KolSettings
    $kolSettings.withLock { $0.llmPostProcessingEnabled = true }

    let store = Self.makeStore { deps in
      deps.keychain.load = { _ in "test-api-key" }
      deps.llmPostProcessing.process = { context, _, _ in
        LLMProcessingResult(
          text: "processed",
          metadata: LLMMetadata(originalText: context.text)
        )
      }
      deps.transcriptPersistence.save = { result, _, _, _, _, _ in
        Transcript(timestamp: Date(), text: result, audioPath: URL(fileURLWithPath: "/tmp/out.wav"), duration: 1.0)
      }
      deps.pasteboard.paste = { _ in }
    }

    await store.send(.startRecording) {
      $0.isRecording = true
    }

    // Simulate transcription result — isPostProcessing set synchronously when LLM enabled
    let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
    await store.send(.transcriptionResult("hello world", audioURL)) {
      $0.isTranscribing = false
      $0.isPostProcessing = true
    }

    // postProcessingFinished should clear it
    await store.receive(\.postProcessingFinished) {
      $0.isPostProcessing = false
    }
  }
}
