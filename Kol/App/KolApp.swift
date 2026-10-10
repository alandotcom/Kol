import AppKit
import ComposableArchitecture
import SwiftUI

extension Notification.Name {
    static let presentKolSettings = Notification.Name("presentKolSettings")
}

@main
struct KolApp: App {
    static let appStore = Store(initialState: AppFeature.State()) { AppFeature() }
    @NSApplicationDelegateAdaptor(KolAppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            KolMenuContents()
        } label: {
            KolMenuLabel(appDelegate: appDelegate)
        }

        Settings {
            AppView(store: Self.appStore)
        }

        Window("History", id: "history") {
            HistoryView(store: Self.appStore.scope(state: \.history, action: \.history))
                .frame(minWidth: 700, minHeight: 420)
        }
        .defaultSize(width: 850, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Kol") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}

private struct KolMenuContents: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuBarCopyLastTranscriptButton()
        Button("History") {
            openWindow(id: "history")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("About Kol") {
            NSApp.orderFrontStandardAboutPanel(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Kol") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct KolMenuLabel: View {
    @Environment(\.openSettings) private var openSettings
    let appDelegate: KolAppDelegate

    var body: some View {
        Image("KolIcon")
            .renderingMode(.template)
            .accessibilityLabel("Kol")
            .onAppear {
                appDelegate.openNativeSettings = { openSettings() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .presentKolSettings)) { _ in
                appDelegate.presentSettingsView()
            }
    }
}
