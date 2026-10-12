import Foundation

public enum LocalCleanupDeadline {
    public static func run(timeout: Duration = .milliseconds(450), operation: @escaping @Sendable () async throws -> LLMProcessingResult) async throws -> LLMProcessingResult {
        let completion = Completion()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard completion.start(continuation) else { return }
                let worker = Task.detached(priority: .userInitiated) {
                    do {
                        try Task.checkCancellation()
                        let result = try await operation()
                        completion.finish(ContinuousClock.now < deadline ? .success(result) : .failure(URLError(.timedOut)))
                    }
                    catch { completion.finish(.failure(error)) }
                }
                let timer = DispatchWorkItem {
                    completion.finish(.failure(URLError(.timedOut)))
                }
                let duration = ContinuousClock.now.duration(to: deadline).components
                let seconds = max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
                completion.track(worker, timer: timer)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds, execute: timer)
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()))
        }
    }

    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<LLMProcessingResult, Error>?
        private var result: Result<LLMProcessingResult, Error>?
        private var worker: Task<Void, Never>?
        private var timer: DispatchWorkItem?

        func start(_ continuation: CheckedContinuation<LLMProcessingResult, Error>) -> Bool {
            let result = lock.withLock {
                if self.result == nil { self.continuation = continuation }
                return self.result
            }
            if let result { continuation.resume(with: result) }
            return result == nil
        }

        func track(_ worker: Task<Void, Never>, timer: DispatchWorkItem) {
            let finished = lock.withLock {
                guard result == nil else { return true }
                self.worker = worker
                self.timer = timer
                return false
            }
            if finished { worker.cancel(); timer.cancel() }
        }

        func finish(_ result: Result<LLMProcessingResult, Error>) {
            let pending = lock.withLock { () -> (CheckedContinuation<LLMProcessingResult, Error>?, Task<Void, Never>?, DispatchWorkItem?)? in
                guard self.result == nil else { return nil }
                self.result = result
                let pending = (continuation, worker, timer)
                continuation = nil
                worker = nil
                timer = nil
                return pending
            }
            guard let pending else { return }
            pending.1?.cancel()
            pending.2?.cancel()
            pending.0?.resume(with: result)
        }
    }
}
