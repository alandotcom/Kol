import Dependencies
import DependenciesMacros
import Foundation

/// Provides keyboard input source detection without importing Carbon.
@DependencyClient
public struct InputSourceClient: Sendable {
	/// Returns true if the current keyboard input source is Hebrew.
	public var isHebrewKeyboardActive: @Sendable () -> Bool = { false }
}

extension InputSourceClient: TestDependencyKey {
	public static let testValue = InputSourceClient()
}

public extension DependencyValues {
	var inputSource: InputSourceClient {
		get { self[InputSourceClient.self] }
		set { self[InputSourceClient.self] = newValue }
	}
}
