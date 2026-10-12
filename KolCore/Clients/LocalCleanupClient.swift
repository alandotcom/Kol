import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LocalCleanupClient: Sendable {
    public var process: @Sendable (_ context: PostProcessingContext) async throws -> LLMProcessingResult
    public var warmUp: @Sendable () async -> Void = {}
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
