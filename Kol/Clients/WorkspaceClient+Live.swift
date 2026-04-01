import AppKit
import Dependencies
import KolCore

extension WorkspaceClient: DependencyKey {
	public static var liveValue: WorkspaceClient {
		WorkspaceClient(
			frontmostApplication: {
				guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
				return FrontmostApp(
					bundleIdentifier: app.bundleIdentifier,
					localizedName: app.localizedName,
					processIdentifier: app.processIdentifier
				)
			}
		)
	}
}
