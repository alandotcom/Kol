import Foundation
import Testing
@testable import KolCore

struct LocalCleanupDeadlineTests {
    @Test func returnsSuccessfulCleanup() async throws {
        let result = try await LocalCleanupDeadline.run(timeout: .seconds(5)) {
            LLMProcessingResult(text: "Ready.", metadata: LLMMetadata(originalText: "ready", model: "local"))
        }
        #expect(result.text == "Ready.")
    }

    @Test func timesOutWithoutWaitingForUncooperativeWork() async {
        let work = PendingWork()
        do {
            _ = try await LocalCleanupDeadline.run(timeout: .milliseconds(20)) {
                await work.wait()
                return LLMProcessingResult(text: "Late.", metadata: LLMMetadata(originalText: "late", model: "local"))
            }
            Issue.record("Expected timeout")
        } catch {
            #expect((error as? URLError)?.code == .timedOut)
        }
        await work.release()
    }

    @Test func cancellationWinsBeforeLateCompletion() async {
        let task = Task {
            try await LocalCleanupDeadline.run {
                try await Task.sleep(for: .seconds(1))
                return LLMProcessingResult(text: "Late.", metadata: LLMMetadata(originalText: "late", model: "local"))
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }

    private actor PendingWork {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            guard !released else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
