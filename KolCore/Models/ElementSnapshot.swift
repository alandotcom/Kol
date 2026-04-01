import Foundation

/// A lightweight snapshot of a focused accessibility element's identity and text content.
/// Used by EditTrackingClient to detect whether the cursor is still in the same field.
public struct ElementSnapshot: Sendable, Equatable {
    /// Hash of the element's role, title, and PID for identity tracking.
    public var hash: Int
    /// The text content of the element at capture time.
    public var text: String

    public init(hash: Int, text: String) {
        self.hash = hash
        self.text = text
    }
}
