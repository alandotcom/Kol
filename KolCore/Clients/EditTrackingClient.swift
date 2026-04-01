import Dependencies
import DependenciesMacros
import Foundation

/// Reads the focused text element for post-paste edit tracking.
@DependencyClient
public struct EditTrackingClient: Sendable {
	/// Capture a snapshot of the currently focused text element.
	public var captureSnapshot: @Sendable () -> ElementSnapshot? = { nil }

	/// Re-read the focused element's text, verifying it matches the given hash.
	/// Returns nil if the element changed or can't be read.
	public var readText: @Sendable (_ expectedHash: Int) -> String? = { _ in nil }
}

extension EditTrackingClient: TestDependencyKey {
	public static let testValue = EditTrackingClient()
}

public extension DependencyValues {
	var editTracking: EditTrackingClient {
		get { self[EditTrackingClient.self] }
		set { self[EditTrackingClient.self] = newValue }
	}
}
