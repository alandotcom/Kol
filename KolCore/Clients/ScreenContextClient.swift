import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct ScreenContextClient: Sendable {
    /// Captures focused text and window vocabulary from the recorded application.
    public var capture: @Sendable (_ sourceApplication: FrontmostApp?) -> TextSourceSnapshot? = { _ in nil }
}

extension ScreenContextClient: TestDependencyKey {
    public static let testValue = ScreenContextClient()
}

public extension DependencyValues {
    var screenContext: ScreenContextClient {
        get { self[ScreenContextClient.self] }
        set { self[ScreenContextClient.self] = newValue }
    }
}
