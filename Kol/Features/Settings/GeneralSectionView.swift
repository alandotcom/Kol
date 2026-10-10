import ComposableArchitecture
import SwiftUI

struct GeneralSectionContent: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { store.kolSettings.openOnLogin },
            set: { store.send(.toggleOpenOnLogin($0)) }
        ))
        Toggle("Show Dock icon", isOn: Binding(
            get: { store.kolSettings.showDockIcon },
            set: { store.send(.toggleShowDockIcon($0)) }
        ))
    }
}

struct RecordingSettingsContent: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Toggle("Prevent sleep while recording", isOn: Binding(
            get: { store.kolSettings.preventSystemSleep },
            set: { store.send(.togglePreventSystemSleep($0)) }
        ))
        Toggle("Keep microphone ready", isOn: Binding(
            get: { store.kolSettings.superFastModeEnabled },
            set: { store.send(.toggleSuperFastMode($0)) }
        ))
        Text("Starts recording faster. macOS keeps the microphone indicator visible.")
            .settingsCaption()
        Toggle("Skip recordings without speech", isOn: Binding(
            get: { store.kolSettings.vadSilenceDetectionEnabled },
            set: { store.send(.setVADSilenceDetection($0)) }
        ))
        Picker("Audio during recording", selection: Binding(
            get: { store.kolSettings.recordingAudioBehavior },
            set: { store.send(.setRecordingAudioBehavior($0)) }
        )) {
            Text("Pause media").tag(RecordingAudioBehavior.pauseMedia)
            Text("Mute volume").tag(RecordingAudioBehavior.mute)
            Text("Leave audio playing").tag(RecordingAudioBehavior.doNothing)
        }
    }
}

struct TextInsertionSettingsContent: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Toggle("Use clipboard to insert text", isOn: Binding(
            get: { store.kolSettings.useClipboardPaste },
            set: { store.send(.setUseClipboardPaste($0)) }
        ))
        Text("Clipboard insertion is faster and may replace clipboard content. Turn off to simulate typing.")
            .settingsCaption()
        Toggle("Append a space after dictation", isOn: Binding(
            get: { store.kolSettings.appendSpaceAfterDictation },
            set: { store.send(.setAppendSpaceAfterDictation($0)) }
        ))
        Text("Adds a space when inserted text does not already end in whitespace.")
            .settingsCaption()
        Toggle("Copy transcription to clipboard", isOn: Binding(
            get: { store.kolSettings.copyToClipboard },
            set: { store.send(.setCopyToClipboard($0)) }
        ))
    }
}

struct TextCleanupSettingsContent: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Toggle("Remove filler words", isOn: Binding(
            get: { store.kolSettings.removeFillerWords },
            set: { store.send(.setRemoveFillerWords($0)) }
        ))
        Text("Removes standalone um, uh, and ah locally before AI processing. AI processing may also remove fillers independently.")
            .settingsCaption()
    }
}
