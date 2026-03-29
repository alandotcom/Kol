import ComposableArchitecture
import KolCore
import Inject
import SwiftUI

struct SoundSectionContent: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		let sliderBinding = Binding<Double>(
			get: { volumePercentage(for: store.kolSettings.soundEffectsVolume) },
			set: { store.send(.setSoundEffectsVolume(actualVolume(fromPercentage: $0))) }
		)

		let themeBinding = Binding<SoundTheme>(
			get: { store.kolSettings.soundTheme },
			set: { store.send(.setSoundTheme($0)) }
		)

		Toggle(
			"Sound Effects",
			isOn: Binding(
				get: { store.kolSettings.soundEffectsEnabled },
				set: { store.send(.setSoundEffectsEnabled($0)) }
			)
		)

		HStack {
			Text("Sound Theme")
			Spacer()
			Picker("", selection: themeBinding) {
				ForEach(SoundTheme.allCases, id: \.self) { theme in
					Text(theme.rawValue.capitalized).tag(theme)
				}
			}
			.pickerStyle(.menu)
			.frame(width: 120)
		}
		.disabled(!store.kolSettings.soundEffectsEnabled)

		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Volume")
				Spacer()
				Text(formattedVolume(for: store.kolSettings.soundEffectsVolume))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			Slider(value: sliderBinding, in: 0...1)
				.disabled(!store.kolSettings.soundEffectsEnabled)
		}

		EmptyView()
			.enableInjection()
	}
}

private func formattedVolume(for actualVolume: Double) -> String {
	let percent = volumePercentage(for: actualVolume)
	return "\(Int(round(percent * 100)))%"
}

private func volumePercentage(for actualVolume: Double) -> Double {
	guard KolSettings.baseSoundEffectsVolume > 0 else { return 0 }
	let ratio = actualVolume / KolSettings.baseSoundEffectsVolume
	return max(0, min(1, ratio))
}

private func actualVolume(fromPercentage percentage: Double) -> Double {
	let clampedPercentage = max(0, min(1, percentage))
	return clampedPercentage * KolSettings.baseSoundEffectsVolume
}
