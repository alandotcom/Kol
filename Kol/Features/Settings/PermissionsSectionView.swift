import ComposableArchitecture
import SwiftUI

struct PermissionsSectionContent: View {
    @Bindable var store: StoreOf<SettingsFeature>
    let microphonePermission: PermissionStatus
    let accessibilityPermission: PermissionStatus
    let inputMonitoringPermission: PermissionStatus

    var body: some View {
        permissionRow("Microphone", status: microphonePermission) { store.send(.requestMicrophone) }
        permissionRow("Accessibility", status: accessibilityPermission) { store.send(.requestAccessibility) }
        permissionRow("Input Monitoring", status: inputMonitoringPermission) { store.send(.requestInputMonitoring) }
    }

    private func permissionRow(_ title: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if status == .granted {
                Label("Allowed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button("Allow…", action: action)
                    .accessibilityLabel("Allow \(title)")
            }
        }
    }
}
