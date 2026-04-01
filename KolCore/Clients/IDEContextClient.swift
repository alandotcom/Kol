import Dependencies
import DependenciesMacros
import Foundation

/// Extracts IDE-specific context (open file names) from the AX tree of code editors.
/// Uses raw AX API to walk the window's toolbar/tab bar and extract tab titles.
@DependencyClient
public struct IDEContextClient: Sendable {
	/// Extract open file names from the IDE tab bar for the given process.
	public var extractTabTitles: @Sendable (_ pid: pid_t) -> [String] = { _ in [] }
}

extension IDEContextClient: TestDependencyKey {
	public static let testValue = IDEContextClient()
}

public extension DependencyValues {
	var ideContext: IDEContextClient {
		get { self[IDEContextClient.self] }
		set { self[IDEContextClient.self] = newValue }
	}
}
