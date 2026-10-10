import ComposableArchitecture
import Clocks
import Foundation
import Testing

@testable import KolCore

@Suite @MainActor
struct TranscriptionLifecycleTests {
  private func state(preventSleep: Bool = false) -> TranscriptionFeature.State {
    var settings = KolSettings()
    settings.llmPostProcessingEnabled = false
    settings.llmScreenContextEnabled = false
    settings.preventSystemSleep = preventSleep
    settings.saveTranscriptionHistory = true
    settings.removeFillerWords = false
    settings.wordRemovalsEnabled = false
    let state = TranscriptionFeature.State(
      kolSettings: Shared(value: settings),
      modelBootstrapState: Shared(value: ModelBootstrapState()),
      transcriptionHistory: Shared(value: TranscriptionHistory())
    )
    state.$isRemappingScratchpadFocused = Shared(value: false)
    return state
  }

  private static func testDependencies(
    _ dependencies: inout DependencyValues,
    recorder: LifecycleTestRecorder,
    pasted: LockIsolated<[String]>
  ) {
    dependencies.date.now = Date(timeIntervalSince1970: 100)
    dependencies.recording.startRecording = { id in await recorder.start(id, take: "old") }
    dependencies.recording.stopRecording = { id in await recorder.stop(id) }
    dependencies.recording.discardRecording = { id in await recorder.discard(id) }
    dependencies.workspace.frontmostApplication = { nil }
    dependencies.keychain = KeychainClient(save: { _, _ in }, load: { _ in nil }, delete: { _ in })
    dependencies.llmPostProcessing = LLMPostProcessingClient(process: { context, _, _ in
      LLMProcessingResult(text: context.text, metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
    })
    dependencies.transcription.transcribe = { _, _, _, _, _, _ in "current text" }
    dependencies.pasteboard.paste = { text, isCurrent in
      try Task.checkCancellation()
      guard await isCurrent() else { throw CancellationError() }
      pasted.withValue { $0.append(text) }
    }
    dependencies.transcriptPersistence = TranscriptPersistenceClient(
      save: { text, metadata, url, duration, bundleID, appName, timing in
        let archiveURL = url.appendingPathExtension("archived")
        try FileManager.default.moveItem(at: url, to: archiveURL)
        return Transcript(
          timestamp: Date(timeIntervalSince1970: 100),
          text: text,
          audioPath: archiveURL,
          duration: duration,
          sourceAppBundleID: bundleID,
          sourceAppName: appName,
          llmMetadata: metadata,
          pipelineTiming: timing
        )
      },
      deleteAudio: { transcript in try FileManager.default.removeItem(at: transcript.audioPath) }
    )
  }

  private func finishCurrentRecording(
    _ store: TestStoreOf<TranscriptionFeature>,
    recorder: LifecycleTestRecorder,
    pasted: LockIsolated<[String]>
  ) async {
    store.dependencies.recording.discardRecording = { id in await recorder.discard(id) }
    store.dependencies.recording.startRecording = { id in await recorder.start(id, take: "current") }
    store.dependencies.date.now = Date(timeIntervalSince1970: 200)
    await store.send(.startRecording)
    await store.finish()
    #expect(await recorder.activeTake == "current")
    #expect(store.state.isRecording == true)
    store.dependencies.date.now = Date(timeIntervalSince1970: 202)
    await store.send(.stopRecording)
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(await recorder.activeTake == nil)
    #expect(store.state.isRecording == false)
    #expect(store.state.transcriptionHistory.history.first?.text == "current text")
    #expect(pasted.value.last == "current text")
    if let url = store.state.transcriptionHistory.history.first?.audioPath {
      #expect(FileManager.default.fileExists(atPath: url.path))
      try? FileManager.default.removeItem(at: url)
    }
  }

  @Test("Cancelling before effect admission prevents startup and context timers")
  func cancelledBeforeEffectAdmission() async throws {
    let clock = TestClock()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let starts = LockIsolated<[UUID]>([])
    let initial = state()
    initial.$kolSettings.withLock { $0.llmScreenContextEnabled = true }
    let store = Store(initialState: initial) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.continuousClock = clock
      $0.llmVocabulary = LLMVocabularyClient(extractNames: { _, _, _, _ in [] })
      $0.screenContext.capture = { _ in nil }
      $0.recording.startRecording = { id in
        starts.withValue { $0.append(id) }
        return await recorder.start(id, take: "current")
      }
    }
    let startup = store.send(.startRecording)
    let cancellation = store.send(.cancel)
    defer { startup.cancel() }
    await cancellation.finish()
    await clock.advance(by: .seconds(1))
    #expect(starts.value.isEmpty)
    try await clock.checkSuspension()
    await startup.finish()
    #expect(store.phase == nil)
    #expect(await recorder.activeTake == nil)

    initial.$kolSettings.withLock { $0.llmScreenContextEnabled = false }
    await store.send(.startRecording).finish()
    #expect(starts.value.count == 1)
    #expect(store.phase == .recording)
    #expect(await recorder.activeTake == "current")
    await store.send(.cancel).finish()
    #expect(await recorder.activeTake == nil)
  }

  @Test("KOL-05 cancelled startup cannot acquire the microphone after acquisition resumes")
  func cancelledStartup() async {
    let startup = LifecycleTestGate<Void>()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state(preventSleep: true)) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.recording.startRecording = { id in
        await startup.wait()
        return await recorder.start(id, take: "old")
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await startup.waitUntilRequested()
    #expect(store.state.isRecording == true)
    await store.send(.cancel).finish()
    await startup.release(())
    await store.finish()
    #expect(store.state.isRecording == false)
    #expect(await recorder.activeTake == nil)
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  @Test("KOL-05 old cancellation cleanup cannot stop a replacement take")
  func delayedCancellationCleanup() async {
    let cleanup = LifecycleTestGate<Void>()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.recording.discardRecording = { id in
        await cleanup.wait()
        await recorder.discard(id)
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.finish()
    #expect(await recorder.activeTake == "old")
    await store.send(.cancel)
    await cleanup.waitUntilRequested()
    store.dependencies.recording.startRecording = { id in await recorder.start(id, take: "replacement") }
    await store.send(.startRecording)
    await store.receive(\.recordingStarted)
    await cleanup.release(())
    await store.finish()
    #expect(store.state.isRecording == true)
    #expect(await recorder.activeTake == "replacement")
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  enum ArchiveInterruption: CaseIterable, Sendable {
    case cancel
    case replacement
  }

  @Test("KOL-04 interrupted archival cannot append history or paste old text", arguments: ArchiveInterruption.allCases)
  func interruptedArchive(_ interruption: ArchiveInterruption) async {
    let archive = LifecycleTestGate<Void>()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      let immediateSave = $0.transcriptPersistence.save
      $0.transcriptPersistence.save = { text, metadata, url, duration, bundleID, appName, timing in
        if text == "old text" { await archive.wait() }
        return try await immediateSave(text, metadata, url, duration, bundleID, appName, timing)
      }
      $0.transcription.transcribe = { _, _, _, _, _, _ in "old text" }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.finish()
    #expect(await recorder.activeTake == "old")
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await store.receive(\.postProcessingFinished)
    await archive.waitUntilRequested()
    let oldAudio = await recorder.exportedURLs.first
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    if let oldAudio { #expect(FileManager.default.fileExists(atPath: oldAudio.path)) }
    switch interruption {
    case .cancel:
      await store.send(.cancel)
      #expect(store.state.contextSession == nil)
    case .replacement:
      store.dependencies.recording.startRecording = { id in await recorder.start(id, take: "replacement") }
      await store.send(.startRecording).finish()
    }
    await archive.release(())
    await store.finish()
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    if let oldAudio {
      #expect(!FileManager.default.fileExists(atPath: oldAudio.path))
      #expect(!FileManager.default.fileExists(atPath: oldAudio.appendingPathExtension("archived").path))
    }
    if interruption == .replacement {
      #expect(await recorder.activeTake == "replacement")
      #expect(store.state.isRecording == true)
    }
    store.dependencies.transcription.transcribe = { _, _, _, _, _, _ in "current text" }
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  @Test("The current recording archives and pastes its transcript")
  func currentRecordingCompletes() async {
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) {
      TranscriptionFeature()
    } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
    }
    store.exhaustivity = .off
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
    #expect(store.state.transcriptionHistory.history.map(\.text) == ["current text"])
    #expect(pasted.value == ["current text"])
  }

  @Test("A refused microphone start clears the indicator and permits a later recording")
  func startupFailure() async {
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.recording.startRecording = { _ in .failed(.unavailable) }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.receive(\.recordingStarted)
    await store.finish()
    #expect(store.state.phase == nil)
    #expect(store.state.error == "The microphone could not start recording.")
    #expect(await recorder.activeTake == nil)
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  @Test("Repeated stop produces one transcript and leaves the next take recording")
  func duplicateStop() async {
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.finish()
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await store.send(.stopRecording)
    await store.finish()
    #expect(pasted.value == ["current text"])
    #expect(store.state.transcriptionHistory.history.map(\.text) == ["current text"])
    store.dependencies.recording.startRecording = { id in await recorder.start(id, take: "replacement") }
    await store.send(.startRecording)
    await store.finish()
    #expect(await recorder.activeTake == "replacement")
    await store.send(.discard)
    await store.send(.discard)
    await store.finish()
    #expect(await recorder.activeTake == nil)
    for transcript in store.state.transcriptionHistory.history {
      try? FileManager.default.removeItem(at: transcript.audioPath)
    }
  }

  @Test("Stopping during acquisition preserves a complete current take", arguments: [false, true])
  func pendingStop(_ repeatStop: Bool) async {
    let startup = LifecycleTestGate<Void>()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.recording.startRecording = { id in
        await startup.wait()
        return await recorder.start(id, take: "current")
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await startup.waitUntilRequested()
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    #expect(store.state.phase == .acquiring(stopRequested: true))
    if repeatStop {
      store.dependencies.date.now = Date(timeIntervalSince1970: 105)
      await store.send(.stopRecording)
      #expect(store.state.recordingDuration == 2)
    }
    await startup.release(())
    await store.receive(\.contextSessionFinished)
    await store.finish()
    #expect(store.state.phase == nil)
    #expect(pasted.value == ["current text"])
    #expect(store.state.transcriptionHistory.history.first?.duration == 2)
    for transcript in store.state.transcriptionHistory.history {
      try? FileManager.default.removeItem(at: transcript.audioPath)
    }
  }

  @Test("Interrupted late ASR and provider results dispose their audio", arguments: [false, true], ArchiveInterruption.allCases)
  func cancelledPipeline(_ provider: Bool, _ interruption: ArchiveInterruption) async throws {
    let response = LifecycleTestGate<String>()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let initial = state()
    if provider { initial.$kolSettings.withLock { $0.llmPostProcessingEnabled = true } }
    let store = TestStore(initialState: initial) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      if provider {
        $0.keychain.load = { _ in "synthetic-key" }
        $0.llmPostProcessing.process = { context, _, _ in
          LLMProcessingResult(text: await response.wait(), metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
        }
      } else {
        $0.transcription.transcribe = { _, _, _, _, _, _ in await response.wait() }
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.finish()
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    if provider { await store.receive(\.transcriptionResult) }
    await response.waitUntilRequested()
    let url = try #require(await recorder.exportedURLs.first)
    #expect(FileManager.default.fileExists(atPath: url.path))
    switch interruption {
    case .cancel: await store.send(.cancel)
    case .replacement:
      store.dependencies.recording.startRecording = { id in await recorder.start(id, take: "replacement") }
      await store.send(.startRecording).finish()
    }
    await response.release("old text")
    await store.finish()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    if interruption == .replacement { #expect(await recorder.activeTake == "replacement") }
    store.state.$kolSettings.withLock { $0.llmPostProcessingEnabled = false }
    store.dependencies.transcription.transcribe = { _, _, _, _, _, _ in "current text" }
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  @Test("Cancel during paste retains committed history and suppresses insertion")
  func cancelledInsertion() async {
    let insertion = LifecycleTestGate<Void>()
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.pasteboard.paste = { text, isCurrent in
        await insertion.wait()
        try Task.checkCancellation()
        guard await isCurrent() else { throw CancellationError() }
        pasted.withValue { $0.append(text) }
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.finish()
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await store.receive(\.archived)
    await insertion.waitUntilRequested()
    #expect(store.state.transcriptionHistory.history.map(\.text) == ["current text"])
    await store.send(.cancel)
    await insertion.release(())
    await store.finish()
    #expect(pasted.value.isEmpty)
    #expect(store.state.transcriptionHistory.history.map(\.text) == ["current text"])
    store.dependencies.pasteboard.paste = { text, isCurrent in
      guard await isCurrent() else { throw CancellationError() }
      pasted.withValue { $0.append(text) }
    }
    for transcript in store.state.transcriptionHistory.history {
      try? FileManager.default.removeItem(at: transcript.audioPath)
    }
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  @Test("Recorder admission rejects retired and cancelled IDs while preserving the active owner")
  func recorderAdmission() {
    let first = UUID(), second = UUID()
    var slot = RecordingTakeSlot()
    let operation0 = slot.admit(first, cancelled: false)
    #expect(operation0 == true)
    #expect(slot.activeID == first)
    let operation1 = slot.admit(second, cancelled: true)
    #expect(operation1 == false)
    #expect(slot.activeID == first)
    let operation2 = slot.admit(second, cancelled: false)
    #expect(operation2 == true)
    let operation3 = slot.finish(first)
    #expect(operation3 == false)
    #expect(slot.activeID == second)
    #expect(slot.canAdmit(first, cancelled: false) == false)
    let operation4 = slot.admit(first, cancelled: false)
    #expect(operation4 == false)
    let operation5 = slot.finish(second)
    #expect(operation5 == true)
    let operation6 = slot.admit(second, cancelled: false)
    #expect(operation6 == false)
  }

  @Test("Media compensation completes before a replacement pause")
  func orderedMediaCompensation() async {
    let pause = LifecycleTestGate<Void>()
    let events = LockIsolated<[String]>([])
    var chain = RecordingMediaTaskChain()
    chain.enqueue { await pause.wait(); events.withValue { $0.append("old pause") } }
    await pause.waitUntilRequested()
    chain.enqueue { events.withValue { $0.append("old restore") } }
    chain.enqueue { events.withValue { $0.append("replacement pause") } }
    await pause.release(())
    await chain.finish()
    #expect(events.value == ["old pause", "old restore", "replacement pause"])
  }

  @Test("Rejected archive completion deletes only its uncommitted audio")
  func staleArchiveDisposal() async throws {
    let stale = FileManager.default.temporaryDirectory.appendingPathComponent("kol-synthetic-stale-\(UUID().uuidString).wav")
    let retained = FileManager.default.temporaryDirectory.appendingPathComponent("kol-synthetic-retained-\(UUID().uuidString).wav")
    try Data("stale audio".utf8).write(to: stale)
    try Data("retained audio".utf8).write(to: retained)
    defer { try? FileManager.default.removeItem(at: stale); try? FileManager.default.removeItem(at: retained) }
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let store = TestStore(initialState: state()) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
    }
    store.exhaustivity = .off
    await store.send(.archived(generation: UUID(), Transcript(timestamp: Date(timeIntervalSince1970: 100), text: "old text", audioPath: stale, duration: 2)))
    await store.finish()
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(try String(contentsOf: retained, encoding: .utf8) == "retained audio")
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }

  @Test("An empty provider result disposes audio and finishes without history or paste")
  func emptyProviderResult() async throws {
    let recorder = LifecycleTestRecorder()
    let pasted = LockIsolated<[String]>([])
    let initial = state()
    initial.$kolSettings.withLock { $0.llmPostProcessingEnabled = true }
    let store = TestStore(initialState: initial) { TranscriptionFeature() } withDependencies: {
      Self.testDependencies(&$0, recorder: recorder, pasted: pasted)
      $0.keychain.load = { _ in "synthetic-key" }
      $0.llmPostProcessing.process = { context, _, _ in
        LLMProcessingResult(text: "  ", metadata: LLMMetadata(originalText: context.text, model: "synthetic"))
      }
    }
    store.exhaustivity = .off
    await store.send(.startRecording)
    await store.finish()
    store.dependencies.date.now = Date(timeIntervalSince1970: 102)
    await store.send(.stopRecording)
    await store.receive(\.contextSessionFinished)
    await store.finish()
    let url = try #require(await recorder.exportedURLs.first)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(store.state.phase == nil)
    #expect(store.state.transcriptionHistory.history.isEmpty)
    #expect(pasted.value.isEmpty)
    store.state.$kolSettings.withLock { $0.llmPostProcessingEnabled = false }
    await finishCurrentRecording(store, recorder: recorder, pasted: pasted)
  }
}

private actor LifecycleTestRecorder {
  private(set) var activeTake: String?
  private(set) var exportedURLs: [URL] = []
  private var slot = RecordingTakeSlot()

  func start(_ id: UUID, take: String) -> RecordingStartOutcome {
    if slot.owns(id) { return .started }
    guard slot.admit(id, cancelled: Task.isCancelled) else { return .superseded }
    activeTake = take
    return .started
  }

  func stop(_ id: UUID) -> RecordingStopOutcome {
    guard !Task.isCancelled, slot.finish(id), let take = activeTake else { return .stale }
    activeTake = nil
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kol-synthetic-take-\(take)-\(UUID().uuidString).wav")
    do { try Data("synthetic audio".utf8).write(to: url) }
    catch { return .failed(.backend(error.localizedDescription)) }
    exportedURLs.append(url)
    return .audio(url)
  }

  func discard(_ id: UUID) {
    guard slot.finish(id) else { return }
    activeTake = nil
  }
}

private actor LifecycleTestGate<Value: Sendable> {
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
