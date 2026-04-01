import Dependencies
import DependenciesMacros
import Foundation

/// Info about the frontmost application, extracted from NSWorkspace.
public struct FrontmostApp: Sendable, Equatable {
	public var bundleIdentifier: String?
	public var localizedName: String?
	public var processIdentifier: pid_t

	public init(bundleIdentifier: String?, localizedName: String?, processIdentifier: pid_t) {
		self.bundleIdentifier = bundleIdentifier
		self.localizedName = localizedName
		self.processIdentifier = processIdentifier
	}
}

/// Provides access to NSWorkspace information without importing AppKit.
@DependencyClient
public struct WorkspaceClient: Sendable {
	/// Returns info about the frontmost application, or nil if unavailable.
	public var frontmostApplication: @Sendable () -> FrontmostApp? = { nil }
}

extension WorkspaceClient: TestDependencyKey {
	public static let testValue = WorkspaceClient()
}

public extension DependencyValues {
	var workspace: WorkspaceClient {
		get { self[WorkspaceClient.self] }
		set { self[WorkspaceClient.self] = newValue }
	}
}
