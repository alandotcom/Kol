import ComposableArchitecture
import SwiftUI

struct HistorySectionContent: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Save transcription history", isOn: Binding(
            get: { store.kolSettings.saveTranscriptionHistory },
            set: { store.send(.toggleSaveTranscriptionHistory($0)) }
        ))
        Text("Stores transcription text and audio on your Mac. Turning off history preserves existing entries and stops saving new recordings.")
            .settingsCaption()
        if store.kolSettings.saveTranscriptionHistory {
            Picker("Maximum entries", selection: Binding(
                get: { store.kolSettings.maxHistoryEntries ?? 0 },
                set: { store.send(.setMaxHistoryEntries($0 == 0 ? nil : $0)) }
            )) {
                Text("Unlimited").tag(0)
                ForEach([50, 100, 200, 500, 1000], id: \.self) { Text(String($0)).tag($0) }
            }
            Text("Reducing the limit deletes the oldest entries and their audio immediately.")
                .settingsCaption()
        }
        LabeledContent("Paste last transcript") {
            Button { store.send(.startSettingPasteLastTranscriptHotkey) } label: {
                HotKeyView(
                    modifiers: store.isSettingPasteLastTranscriptHotkey ? store.currentPasteLastModifiers : (store.kolSettings.pasteLastTranscriptHotkey?.modifiers ?? .init(modifiers: [])),
                    key: store.isSettingPasteLastTranscriptHotkey ? nil : store.kolSettings.pasteLastTranscriptHotkey?.key,
                    isActive: store.isSettingPasteLastTranscriptHotkey
                )
            }
            .help("Click to set a shortcut with at least one modifier and a key.")
        }
        if store.isSettingPasteLastTranscriptHotkey {
            HStack {
                Text("Press a modifier and a key. Press Escape to cancel.").settingsCaption()
                Spacer()
                Button("Cancel") { store.send(.cancelShortcutCapture) }
            }
        } else if store.kolSettings.pasteLastTranscriptHotkey != nil {
            Button("Clear paste shortcut") { store.send(.clearPasteLastTranscriptHotkey) }
        }
        Button("Open History") { openWindow(id: "history") }
    }
}
