import ComposableArchitecture
import Inject
import SwiftUI

struct SettingsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let microphonePermission: PermissionStatus
	let accessibilityPermission: PermissionStatus
	let inputMonitoringPermission: PermissionStatus

	var body: some View {
		VStack(alignment: .leading, spacing: 32) {
			SectionHeader(title: "Settings", style: .settings)

			if microphonePermission != .granted
				|| accessibilityPermission != .granted
				|| inputMonitoringPermission != .granted {
				PermissionsSectionContent(
					store: store,
					microphonePermission: microphonePermission,
					accessibilityPermission: accessibilityPermission,
					inputMonitoringPermission: inputMonitoringPermission
				)
			}

			// Transcription Models
			VStack(alignment: .leading, spacing: 20) {
				SectionHeader(title: "Transcription Models", style: .section)
				ModelSectionContent(store: store, shouldFlash: store.shouldFlashModelSection)
				if ParakeetModel(rawValue: store.kolSettings.selectedModel) == nil
					|| QwenModel(rawValue: store.kolSettings.selectedModel) != nil
				{
					LanguageSectionContent(store: store)
				}
			}

			// Hot Key
			VStack(alignment: .leading, spacing: 16) {
				SectionHeader(title: "Hot Key", style: .section)
				HotKeySectionContent(store: store)
			}

			Divider()

			// History settings
			VStack(alignment: .leading, spacing: 16) {
				SectionHeader(title: "History", style: .section)
				HistorySectionContent(store: store)
			}
		}
		.task {
			await store.send(.task).finish()
		}
		.enableInjection()
	}
}

// MARK: - Shared Styles

extension Text {
	func settingsCaption() -> some View {
		self.font(.caption).foregroundStyle(.secondary)
	}
}
