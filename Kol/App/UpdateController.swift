import Combine
import ComposableArchitecture
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    private(set) var isInstallingUpdate = false
    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        #if !DEBUG
        guard !isTesting else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
        )
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloadsUpdates)
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        isInstallingUpdate = true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isInstallingUpdate = false
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        Button("Check for Updates…", action: updates.checkForUpdates)
            .disabled(!updates.canCheckForUpdates)
    }
}

struct UpdateSettingsContent: View {
    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        Toggle("Automatically check for updates", isOn: Binding(
            get: { updates.automaticallyChecksForUpdates },
            set: updates.setAutomaticallyChecksForUpdates
        ))
        .disabled(!updates.isAvailable)
        Toggle("Download updates and install when Kol quits", isOn: Binding(
            get: { updates.automaticallyDownloadsUpdates },
            set: updates.setAutomaticallyDownloadsUpdates
        ))
        .disabled(!updates.isAvailable || !updates.automaticallyChecksForUpdates)
        CheckForUpdatesButton()
        #if DEBUG
        Text("Updates are available in release builds.").settingsCaption()
        #endif
    }
}
