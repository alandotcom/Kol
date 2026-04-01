import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct ScreenContextClient: Sendable {
    public var captureVisibleText: @Sendable (_ sourceAppBundleID: String?) -> String? = { _ in nil }
    /// Returns structured text around the cursor (before/after/selected), or nil on failure.
    public var captureCursorContext: @Sendable (_ sourceAppBundleID: String?) -> CursorContext? = { _ in nil }
    /// Returns the character immediately before the cursor in the focused text field, or nil.
    public var characterBeforeCursor: @Sendable () async -> Character? = { nil }
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
