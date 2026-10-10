import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        SettingsView(
            store: store.scope(state: \.settings, action: \.settings),
            pane: Binding(
                get: { store.settingsPane },
                set: { store.send(.setSettingsPane($0)) }
            ),
            microphonePermission: store.microphonePermission,
            accessibilityPermission: store.accessibilityPermission,
            inputMonitoringPermission: store.inputMonitoringPermission,
            screenRecordingPermission: store.screenRecordingPermission
        )
    }
}
