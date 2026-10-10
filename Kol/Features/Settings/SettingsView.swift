import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Binding var pane: AppFeature.SettingsPane
    let microphonePermission: PermissionStatus
    let accessibilityPermission: PermissionStatus
    let inputMonitoringPermission: PermissionStatus
    let screenRecordingPermission: PermissionStatus

    @State private var showingChangelog = false

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: .general) {
                Form {
                    Section("Application") { GeneralSectionContent(store: store) }
                    Section("Kol") {
                        LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        Button("About Kol") { NSApp.orderFrontStandardAboutPanel(nil) }
                        Button("Release notes") { showingChangelog = true }
                            .sheet(isPresented: $showingChangelog) {
                                ChangelogView().frame(width: 560, height: 600)
                            }
                        Link("Original project", destination: URL(string: "https://github.com/kitlangton/Hex")!)
                        Link("Report an issue", destination: URL(string: "https://github.com/alandotcom/Kol/issues")!)
                    }
                }
            }
            Tab("Recording", systemImage: "mic", value: .recording) {
                Form {
                    Section("Keyboard shortcut") { HotKeySectionContent(store: store) }
                    Section("Microphone") { MicrophoneSectionContent(store: store) }
                    Section("Recording behavior") { RecordingSettingsContent(store: store) }
                }
            }
            Tab("Text", systemImage: "textformat", value: .text) {
                Form {
                    Section("Insertion") { TextInsertionSettingsContent(store: store) }
                    Section("Cleanup") { TextCleanupSettingsContent(store: store) }
                    Section("AI post-processing") {
                        LLMSectionContent(store: store)
                    }
                    WordRemappingsView(store: store)
                }
            }
            Tab("Models", systemImage: "waveform", value: .models) {
                Form {
                    Section("Transcription model") {
                        ModelSectionContent(store: store, shouldFlash: store.shouldFlashModelSection)
                        if ParakeetModel(rawValue: store.kolSettings.selectedModel) == nil {
                            LanguageSectionContent(store: store)
                        }
                    }
                }
            }
            Tab("Privacy", systemImage: "hand.raised", value: .privacy) {
                Form {
                    Section("Permissions") {
                        PermissionsSectionContent(
                            store: store,
                            microphonePermission: microphonePermission,
                            accessibilityPermission: accessibilityPermission,
                            inputMonitoringPermission: inputMonitoringPermission
                        )
                    }
                    Section("Screen context") {
                        ContextPrivacySettingsContent(store: store, screenRecordingPermission: screenRecordingPermission)
                    }
                    Section("History") { HistorySectionContent(store: store) }
                    Section("Processing") {
                        Text("Speech recognition runs on your Mac. When AI post-processing is enabled, transcription text and enabled context are sent to your selected provider.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 610)
        .task { await store.send(.task).finish() }
        .onChange(of: pane) { store.send(.cancelShortcutCapture) }
        .onDisappear { store.send(.cancelShortcutCapture) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            store.send(.cancelShortcutCapture)
        }
    }
}

extension Text {
    func settingsCaption() -> some View { font(.callout).foregroundStyle(.secondary) }
}
