import ComposableArchitecture
import Inject
import SwiftUI

struct LanguageSectionContent: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Picker(
			"Output Language",
			selection: Binding(
				get: { store.kolSettings.outputLanguage },
				set: { store.send(.setOutputLanguage($0)) }
			)
		) {
			ForEach(store.languages, id: \.id) { language in
				Text(language.name).tag(language.code as String?)
			}
		}
		.pickerStyle(.menu)
		.enableInjection()
	}
}
