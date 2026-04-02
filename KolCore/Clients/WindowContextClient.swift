import Dependencies
import DependenciesMacros
import Foundation

/// Extracts window-level metadata from the AX tree: window title and browser URL.
/// Used for conversation awareness and app context reclassification.
@DependencyClient
public struct WindowContextClient: Sendable {
	/// Read the title of the focused window for a process.
	public var windowTitle: @Sendable (_ pid: pid_t) -> String? = { _ in nil }

	/// Extract a URL from a browser's AX tree (address bar content).
	public var browserURL: @Sendable (_ pid: pid_t) -> String? = { _ in nil }
}

extension WindowContextClient: TestDependencyKey {
	public static let testValue = WindowContextClient()
}

public extension DependencyValues {
	var windowContext: WindowContextClient {
		get { self[WindowContextClient.self] }
		set { self[WindowContextClient.self] = newValue }
	}
}
