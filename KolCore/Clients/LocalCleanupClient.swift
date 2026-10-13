import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LocalCleanupClient: Sendable {
    public var process: @Sendable (_ context: PostProcessingContext) async throws -> LLMProcessingResult
    public var warmUp: @Sendable () async -> Void = {}
    /// Wakes the warmed models when recording starts. After minutes of idle time the first Core ML call on the GPU
    /// takes several hundred milliseconds; doing it while the user speaks keeps it out of the cleanup deadline.
    public var prime: @Sendable () async -> Void = {}
    /// True when the cleanup model is on this Mac (bundled or downloaded) and can load.
    public var isModelAvailable: @Sendable () -> Bool = { false }
    /// Downloads, verifies and compiles the cleanup model, reporting the fraction downloaded from 0 to 1.
    public var downloadModel: @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void
}

extension LocalCleanupClient: TestDependencyKey {
    public static let testValue = LocalCleanupClient()
}

public extension DependencyValues {
    var localCleanup: LocalCleanupClient {
        get { self[LocalCleanupClient.self] }
        set { self[LocalCleanupClient.self] = newValue }
    }
}
