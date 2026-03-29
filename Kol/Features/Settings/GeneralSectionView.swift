import ComposableArchitecture
import Inject
import SwiftUI

struct GeneralSectionContent: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Toggle("Open on Login",
		       isOn: Binding(
		       	get: { store.kolSettings.openOnLogin },
		       	set: { store.send(.toggleOpenOnLogin($0)) }
		       ))

		Toggle(
			"Show Dock Icon",
			isOn: Binding(
				get: { store.kolSettings.showDockIcon },
				set: { store.send(.toggleShowDockIcon($0)) }
			)
		)

		VStack(alignment: .leading, spacing: 2) {
			Toggle(
				"Use clipboard to insert",
				isOn: Binding(
					get: { store.kolSettings.useClipboardPaste },
					set: { store.send(.setUseClipboardPaste($0)) }
				)
			)
			Text("Fast but may not restore all clipboard content. Turn off to use simulated keypresses.")
				.settingsCaption()
		}

		VStack(alignment: .leading, spacing: 2) {
			Toggle(
				"Copy to clipboard",
				isOn: Binding(
					get: { store.kolSettings.copyToClipboard },
					set: { store.send(.setCopyToClipboard($0)) }
				)
			)
			Text("Copy transcription text to clipboard in addition to pasting it")
				.settingsCaption()
		}

		Toggle(
			"Prevent System Sleep while Recording",
			isOn: Binding(
				get: { store.kolSettings.preventSystemSleep },
				set: { store.send(.togglePreventSystemSleep($0)) }
			)
		)

		VStack(alignment: .leading, spacing: 2) {
			Toggle(
				"Super Fast Mode",
				isOn: Binding(
					get: { store.kolSettings.superFastModeEnabled },
					set: { store.send(.toggleSuperFastMode($0)) }
				)
			)
			Text("Keep the microphone warm for near-instant capture. macOS will keep showing the microphone indicator.")
				.settingsCaption()
		}

		VStack(alignment: .leading, spacing: 2) {
			Toggle(
				"Silence Detection",
				isOn: Binding(
					get: { store.kolSettings.vadSilenceDetectionEnabled },
					set: { store.send(.setVADSilenceDetection($0)) }
				)
			)
			Text("Skip transcription when no speech is detected. Prevents hallucinated text from background noise.")
				.settingsCaption()
		}

		HStack {
			Text("Audio Behavior while Recording")
			Spacer()
			Picker("", selection: Binding(
				get: { store.kolSettings.recordingAudioBehavior },
				set: { store.send(.setRecordingAudioBehavior($0)) }
			)) {
				Label("Pause Media", systemImage: "pause")
					.tag(RecordingAudioBehavior.pauseMedia)
				Label("Mute Volume", systemImage: "speaker.slash")
					.tag(RecordingAudioBehavior.mute)
				Label("Do Nothing", systemImage: "hand.raised.slash")
					.tag(RecordingAudioBehavior.doNothing)
			}
			.pickerStyle(.menu)
		}

		EmptyView()
			.enableInjection()
	}
}
