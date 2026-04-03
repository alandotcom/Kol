import ComposableArchitecture
import SwiftUI

private let appLogger = KolLog.app
private let cacheLogger = KolLog.caches

@MainActor
class KolAppDelegate: NSObject, NSApplicationDelegate {
	var invisibleWindow: InvisibleWindow?
	var settingsWindow: NSWindow?
	var statusItem: NSStatusItem!
	private var launchedAtLogin = false

	@Dependency(\.soundEffects) var soundEffect
	@Dependency(\.recording) var recording
	@Shared(.kolSettings) var kolSettings: KolSettings

	func applicationDidFinishLaunching(_: Notification) {
		DiagnosticsLogging.bootstrapIfNeeded()
		// Ensure Parakeet/FluidAudio caches live under Application Support, not ~/.cache
		configureLocalCaches()
		if isTesting {
			appLogger.debug("Running in testing mode")
			return
		}

		Task {
			await soundEffect.preloadSounds()
		}
		launchedAtLogin = wasLaunchedAtLogin()
		appLogger.info("Application did finish launching")
		appLogger.notice("launchedAtLogin = \(self.launchedAtLogin)")

		// Set activation policy first
		updateAppMode()

		// Add notification observer
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAppModeUpdate),
			name: .updateAppMode,
			object: nil
		)

		// Start long-running app effects (global hotkeys, permissions, etc.)
		startLifecycleTasksIfNeeded()

		// Then present main views
		presentMainView()

		guard shouldOpenForegroundUIOnLaunch else {
			appLogger.notice("Suppressing foreground windows for login launch")
			return
		}

		presentSettingsView()
		NSApp.activate(ignoringOtherApps: true)
	}

	private var shouldOpenForegroundUIOnLaunch: Bool {
		!(launchedAtLogin && !kolSettings.showDockIcon)
	}

	private func wasLaunchedAtLogin() -> Bool {
		guard let event = NSAppleEventManager.shared().currentAppleEvent else {
			return false
		}

		return event.eventID == AEEventID(kAEOpenApplication)
			&& event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEEventClass(keyAELaunchedAsLogInItem)
	}

	private func startLifecycleTasksIfNeeded() {
		Task { @MainActor in
			await KolApp.appStore.send(.task).finish()
		}
	}

	/// Sets XDG_CACHE_HOME so FluidAudio stores models under our app's
	/// Application Support folder, keeping everything in one place.
    private func configureLocalCaches() {
        do {
            let cache = try URL.kolApplicationSupport.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            setenv("XDG_CACHE_HOME", cache.path, 1)
            cacheLogger.info("XDG_CACHE_HOME set to \(cache.path)")
        } catch {
            cacheLogger.error("Failed to configure local caches: \(error.localizedDescription)")
        }
    }

	func presentMainView() {
		guard invisibleWindow == nil else {
			return
		}
		let transcriptionStore = KolApp.appStore.scope(state: \.transcription, action: \.transcription)
		let transcriptionView = TranscriptionView(store: transcriptionStore).padding().padding(.top).padding(.top)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		invisibleWindow = InvisibleWindow.fromView(transcriptionView)
		invisibleWindow?.makeKeyAndOrderFront(nil)
	}

	func presentSettingsView() {
		if let settingsWindow = settingsWindow {
			settingsWindow.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let settingsView = AppView(store: KolApp.appStore)
		let settingsWindow = NSWindow(
			contentRect: .init(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		settingsWindow.title = "Kol"
		settingsWindow.titleVisibility = .visible
		settingsWindow.titlebarAppearsTransparent = true
		settingsWindow.backgroundColor = .clear
		settingsWindow.isMovableByWindowBackground = true

		let visualEffectView = NSVisualEffectView()
		visualEffectView.blendingMode = .behindWindow
		visualEffectView.material = .sidebar
		visualEffectView.state = .active

		let hostingView = NSHostingView(rootView: settingsView)
		hostingView.translatesAutoresizingMaskIntoConstraints = false
		visualEffectView.addSubview(hostingView)
		NSLayoutConstraint.activate([
			hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
			hostingView.leftAnchor.constraint(equalTo: visualEffectView.leftAnchor),
			hostingView.rightAnchor.constraint(equalTo: visualEffectView.rightAnchor),
			hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
		])
		settingsWindow.contentView = visualEffectView
		settingsWindow.isReleasedWhenClosed = false
		settingsWindow.setFrameAutosaveName("KolSettingsWindow")
		settingsWindow.center()
		settingsWindow.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.settingsWindow = settingsWindow
	}

	@objc private func handleAppModeUpdate() {
		Task { [weak self] in
			self?.updateAppMode()
		}
	}

	@MainActor
	private func updateAppMode() {
		appLogger.debug("showDockIcon = \(self.kolSettings.showDockIcon)")
		if self.kolSettings.showDockIcon {
			NSApp.setActivationPolicy(.regular)
		} else {
			NSApp.setActivationPolicy(.accessory)
		}
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		presentSettingsView()
		return true
	}

	func applicationWillTerminate(_: Notification) {
		NotificationCenter.default.removeObserver(self)
		// Fire-and-forget: Task.detached avoids deadlocking the @MainActor
		// (a plain Task would need the main actor, which is blocked by sema.wait).
		// Best-effort cleanup — the OS will reclaim resources regardless.
		let rec = recording
		let sema = DispatchSemaphore(value: 0)
		Task.detached {
			await rec.cleanup()
			sema.signal()
		}
		_ = sema.wait(timeout: .now() + 2.0)
	}
}
