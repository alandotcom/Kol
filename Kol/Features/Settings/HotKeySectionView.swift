import ComposableArchitecture
import KolCore
import Inject
import SwiftUI

struct HotKeySectionContent: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        let hotKey = store.kolSettings.hotkey
        let key = store.isSettingHotKey ? nil : hotKey.key
        let modifiers = store.isSettingHotKey ? store.currentModifiers : hotKey.modifiers

        VStack(spacing: 0) {
            // Centered hotkey display
            HStack {
                Spacer()
                HotKeyView(modifiers: modifiers, key: key, isActive: store.isSettingHotKey)
                    .animation(.spring(), value: key)
                    .animation(.spring(), value: modifiers)
                Spacer()
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                store.send(.startSettingHotKey)
            }

            // Modifier side controls
            if !store.isSettingHotKey,
               hotKey.key == nil,
               !hotKey.modifiers.isEmpty {
                ModifierSideControls(
                    modifiers: hotKey.modifiers,
                    onSelect: { kind, side in
                        store.send(.setModifierSide(kind, side))
                    }
                )
                .transition(.opacity)
            }

            SettingsRow {
                Text("Enable double-tap lock")
                    .font(.subheadline)
            } trailing: {
                Toggle("", isOn: Binding(
                    get: { store.kolSettings.doubleTapLockEnabled },
                    set: { store.send(.setDoubleTapLockEnabled($0)) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if hotKey.key != nil {
                Divider().background(Color.gray.opacity(0.15))

                SettingsRow {
                    Text("Use double-tap only")
                        .font(.subheadline)
                } trailing: {
                    Toggle("", isOn: Binding(
                        get: { store.kolSettings.useDoubleTapOnly },
                        set: { store.send(.setUseDoubleTapOnly($0)) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!store.kolSettings.doubleTapLockEnabled)
                }
            }

            if store.kolSettings.hotkey.key == nil {
                Divider().background(Color.gray.opacity(0.15))

                VStack(spacing: 12) {
                    HStack {
                        Text("Ignore below \(store.kolSettings.minimumKeyTime, specifier: "%.1f")s")
                            .font(.subheadline)
                        Spacer()
                    }
                    Slider(
                        value: Binding(
                            get: { store.kolSettings.minimumKeyTime },
                            set: { store.send(.setMinimumKeyTime($0)) }
                        ),
                        in: 0.0 ... 2.0,
                        step: 0.1
                    )
                    .tint(.blue)
                }
                .padding(.vertical, 12)
            }
        }

        EmptyView()
            .enableInjection()
    }
}

/// A settings row with label on left and control on right, matching the design.
private struct SettingsRow<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            leading
            Spacer()
            trailing
        }
        .padding(.vertical, 12)
    }
}

private struct ModifierSideControls: View {
    @ObserveInjection var inject
    var modifiers: Modifiers
    var onSelect: (Modifier.Kind, Modifier.Side) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(modifiers.kinds, id: \.self) { kind in
                if kind.supportsSideSelection {
                    let binding = Binding<Modifier.Side>(
                        get: { modifiers.side(for: kind) ?? .either },
                        set: { onSelect(kind, $0) }
                    )

                    HStack {
                        Text("Modifier side")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: binding) {
                            ForEach(Modifier.Side.allCases, id: \.self) { side in
                                Text(side.displayName)
                                    .tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .enableInjection()
    }
}
