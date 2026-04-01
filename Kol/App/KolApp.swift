import ComposableArchitecture
import Inject
import AppKit
import SwiftUI

@main
struct KolApp: App {
	/// Live store — nil when running under XCTest to avoid conflicting
	/// with TestStore dependency injection.
	private static let _appStore: Store<AppFeature.State, AppFeature.Action>? = {
		guard !isTesting else { return nil }
		return Store(initialState: AppFeature.State()) {
			AppFeature()
		}
	}()

	/// Access the live store. Falls back to a no-op store if somehow accessed during tests.
	static var appStore: Store<AppFeature.State, AppFeature.Action> {
		_appStore ?? Store(initialState: AppFeature.State()) { EmptyReducer() }
	}

	@NSApplicationDelegateAdaptor(KolAppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            // Copy last transcript to clipboard
            MenuBarCopyLastTranscriptButton()

            Button("Settings...") {
                appDelegate.presentSettingsView()
            }.keyboardShortcut(",")

			Divider()

			Button("Quit") {
				NSApplication.shared.terminate(nil)
			}.keyboardShortcut("q")
		} label: {
			let image: NSImage = {
				let ratio = $0.size.height / $0.size.width
				$0.size.height = 18
				$0.size.width = 18 / ratio
				return $0
			}(NSImage(named: "KolIcon")!)
			Image(nsImage: image)
		}


		WindowGroup {}.defaultLaunchBehavior(.suppressed)
			.commands {
				CommandGroup(after: .appInfo) {
					Button("Settings...") {
						appDelegate.presentSettingsView()
					}.keyboardShortcut(",")
				}

				CommandGroup(replacing: .help) {}
			}
	}
}
