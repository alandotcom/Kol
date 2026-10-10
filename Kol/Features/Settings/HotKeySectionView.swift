import ComposableArchitecture
import KolCore
import SwiftUI

struct HotKeySectionContent: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        let hotkey = store.kolSettings.hotkey
        let minimumHoldFloor = hotkey.key == nil ? RecordingDecisionEngine.modifierOnlyMinimumDuration : 0
        let effectiveMinimumHold = max(store.kolSettings.minimumKeyTime, minimumHoldFloor)
        LabeledContent("Record") {
            Button { store.send(.startSettingHotKey) } label: {
                HotKeyView(
                    modifiers: store.isSettingHotKey ? store.currentModifiers : hotkey.modifiers,
                    key: store.isSettingHotKey ? nil : hotkey.key,
                    isActive: store.isSettingHotKey
                )
            }
            .help("Click to change the recording shortcut. Press Escape to cancel.")
        }
        if store.isSettingHotKey {
            HStack {
                Text("Press a key or modifier. Press Escape to cancel.").settingsCaption()
                Spacer()
                Button("Cancel") { store.send(.cancelShortcutCapture) }
            }
        }
        if !store.isSettingHotKey, hotkey.key == nil {
            ForEach(hotkey.modifiers.kinds, id: \.self) { kind in
                if kind.supportsSideSelection {
                    Picker("\(kind.displayName) modifier side", selection: Binding<Modifier.Side>(
                        get: { hotkey.modifiers.side(for: kind) ?? .either },
                        set: { store.send(.setModifierSide(kind, $0)) }
                    )) {
                        ForEach(Modifier.Side.allCases, id: \.self) { side in
                            Text(side.displayName).tag(side)
                        }
                    }
                }
            }
        }
        Toggle("Enable double-tap lock", isOn: Binding(
            get: { store.kolSettings.doubleTapLockEnabled },
            set: { store.send(.setDoubleTapLockEnabled($0)) }
        ))
        if hotkey.key != nil {
            Toggle("Use double-tap only", isOn: Binding(
                get: { store.kolSettings.useDoubleTapOnly },
                set: { store.send(.setUseDoubleTapOnly($0)) }
            ))
            .disabled(!store.kolSettings.doubleTapLockEnabled)
        }
        Slider(value: Binding(
            get: { effectiveMinimumHold },
            set: { store.send(.setMinimumKeyTime($0)) }
        ), in: minimumHoldFloor...2, step: 0.1) {
            Text("Minimum hold: \(effectiveMinimumHold, specifier: "%.1f") seconds")
        }
        if hotkey.key == nil {
            Text("Modifier shortcuts require a hold of at least \(minimumHoldFloor, specifier: "%.1f") seconds to avoid accidental recordings.")
                .settingsCaption()
            if store.kolSettings.doubleTapLockEnabled {
                Text("Double-tap to keep recording, then press the shortcut again to stop.")
                    .settingsCaption()
            }
        }
        Text("Press Escape to cancel a recording.").settingsCaption()
    }
}
