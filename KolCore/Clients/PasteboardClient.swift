import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct PasteboardClient: Sendable {
    public var paste: @Sendable (_ text: String, _ isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Void
    public var copy: @Sendable (String) async -> Void
    public var sendKeyboardCommand: @Sendable (KeyboardCommand) async -> Void
}

extension PasteboardClient: TestDependencyKey {
    public static let testValue = PasteboardClient(
        paste: { _, _ in },
        copy: { _ in },
        sendKeyboardCommand: { _ in }
    )
}

public extension DependencyValues {
    var pasteboard: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}
