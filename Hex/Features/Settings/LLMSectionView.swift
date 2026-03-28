import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct LLMSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Label {
			Toggle(
				"AI Post-Processing",
				isOn: Binding(
					get: { store.hexSettings.llmPostProcessingEnabled },
					set: { store.send(.setLLMEnabled($0)) }
				)
			)
		} icon: {
			Image(systemName: "wand.and.stars")
		}

		if store.hexSettings.llmPostProcessingEnabled {
			VStack(alignment: .leading, spacing: 8) {
				// Provider preset
				Picker(
					"Provider",
					selection: Binding(
						get: { store.hexSettings.llmProviderPreset },
						set: { store.send(.setLLMPreset($0)) }
					)
				) {
					ForEach(LLMProviderPreset.allCases, id: \.rawValue) { preset in
						Text(preset.displayName).tag(preset.rawValue)
					}
				}
				.pickerStyle(.segmented)

				// API Key
				HStack {
					SecureField(
						"API Key",
						text: Binding(
							get: { store.llmApiKey },
							set: { store.send(.setLLMApiKey($0)) }
						)
					)
					.textFieldStyle(.roundedBorder)

					if !store.llmApiKey.isEmpty {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
							.font(.caption)
					}
				}

				// Base URL + Model (editable only for custom)
				let isCustom = store.hexSettings.llmProviderPreset == LLMProviderPreset.custom.rawValue

				TextField(
					"Base URL",
					text: Binding(
						get: { store.hexSettings.llmProviderBaseURL },
						set: { store.send(.setLLMBaseURL($0)) }
					)
				)
				.textFieldStyle(.roundedBorder)
				.disabled(!isCustom)
				.opacity(isCustom ? 1 : 0.5)

				TextField(
					"Model",
					text: Binding(
						get: { store.hexSettings.llmModelName },
						set: { store.send(.setLLMModelName($0)) }
					)
				)
				.textFieldStyle(.roundedBorder)
				.disabled(!isCustom)
				.opacity(isCustom ? 1 : 0.5)

				// Custom rules
				VStack(alignment: .leading, spacing: 4) {
					HStack {
						Text("Custom Context")
							.font(.caption)
							.foregroundColor(.secondary)
						Spacer()
						if !store.hexSettings.llmCustomRules.isEmpty {
							Button("Clear") {
								store.send(.setLLMCustomRules(""))
							}
							.font(.caption)
							.buttonStyle(.plain)
							.foregroundColor(.secondary)
						}
					}

					TextEditor(
						text: Binding(
							get: { store.hexSettings.llmCustomRules },
							set: { store.send(.setLLMCustomRules($0)) }
						)
					)
					.frame(height: 60)
					.font(.caption)
					.scrollContentBackground(.hidden)
					.background(Color(.textBackgroundColor).opacity(0.5))
					.cornerRadius(6)
					.overlay(
						Group {
							if store.hexSettings.llmCustomRules.isEmpty {
								Text("e.g. My name is Alan. Common terms: Claude Code, Railway, CoreML")
									.font(.caption)
									.foregroundColor(.secondary.opacity(0.5))
									.padding(.horizontal, 4)
									.padding(.top, 8)
									.allowsHitTesting(false)
							}
						},
						alignment: .topLeading
					)
				}

				// Screen context
				Toggle(
					"Include visible text as context",
					isOn: Binding(
						get: { store.hexSettings.llmScreenContextEnabled },
						set: { store.send(.setLLMScreenContextEnabled($0)) }
					)
				)
				Text("Captures text near the cursor to help recognize technical terms on screen.")
					.font(.caption)
					.foregroundColor(.secondary)

				// App context prompt customization
				Button("Customize App Context Prompts...") {
					store.send(.showPromptCustomization)
				}
				.font(.caption)
			}
			.padding(.leading, 24)
			.sheet(
				isPresented: Binding(
					get: { store.showingPromptCustomization },
					set: { if !$0 { store.send(.dismissPromptCustomization) } }
				)
			) {
				PromptCustomizationView(store: store)
			}
		}
	}
}
