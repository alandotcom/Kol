import ComposableArchitecture
import Inject
import SwiftUI

struct LLMSectionContent: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let screenRecordingPermission: PermissionStatus

	var body: some View {
		Toggle(
			"Enable AI Post-Processing",
			isOn: Binding(
				get: { store.kolSettings.llmPostProcessingEnabled },
				set: { store.send(.setLLMEnabled($0)) }
			)
		)

		if store.kolSettings.llmPostProcessingEnabled {
			VStack(alignment: .leading, spacing: 8) {
				Picker(
					"Provider",
					selection: Binding(
						get: { store.kolSettings.llmProviderPreset },
						set: { store.send(.setLLMPreset($0)) }
					)
				) {
					ForEach(LLMProviderPreset.allCases, id: \.rawValue) { preset in
						Text(preset.displayName).tag(preset.rawValue)
					}
				}
				.pickerStyle(.segmented)

				HStack {
					SecureField(
						"API Key",
						text: Binding(
							get: { store.llmApiKey },
							set: { store.send(.setLLMApiKey($0)) }
						)
					)
					.textFieldStyle(.roundedBorder)
					.accessibilityHint("Enter your LLM provider API key")

					if !store.llmApiKey.isEmpty {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
							.font(.system(size: 13))
					}
				}

				let isCustom = store.kolSettings.llmProviderPreset == LLMProviderPreset.custom.rawValue

				TextField(
					"Base URL",
					text: Binding(
						get: { store.kolSettings.llmProviderBaseURL },
						set: { store.send(.setLLMBaseURL($0)) }
					)
				)
				.textFieldStyle(.roundedBorder)
				.disabled(!isCustom)
				.opacity(isCustom ? 1 : 0.5)

				TextField(
					"Model",
					text: Binding(
						get: { store.kolSettings.llmModelName },
						set: { store.send(.setLLMModelName($0)) }
					)
				)
				.textFieldStyle(.roundedBorder)
				.disabled(!isCustom)
				.opacity(isCustom ? 1 : 0.5)

				VStack(alignment: .leading, spacing: 4) {
					HStack {
						Text("Custom Context")
							.font(.system(size: 13))
							.foregroundColor(.secondary)
						Spacer()
						if !store.kolSettings.llmCustomRules.isEmpty {
							Button("Clear") {
								store.send(.setLLMCustomRules(""))
							}
							.font(.system(size: 13))
							.buttonStyle(.plain)
							.foregroundColor(.secondary)
						}
					}

					TextEditor(
						text: Binding(
							get: { store.kolSettings.llmCustomRules },
							set: { store.send(.setLLMCustomRules($0)) }
						)
					)
					.frame(height: 60)
					.font(.system(size: 13))
					.scrollContentBackground(.hidden)
					.background(Color(.textBackgroundColor).opacity(0.5))
					.cornerRadius(6)
					.overlay(
						Group {
							if store.kolSettings.llmCustomRules.isEmpty {
								Text("e.g. My name is Alan. Common terms: Claude Code, Railway, CoreML")
									.font(.system(size: 13))
									.foregroundColor(.secondary.opacity(0.5))
									.padding(.horizontal, 4)
									.padding(.top, 8)
									.allowsHitTesting(false)
							}
						},
						alignment: .topLeading
					)
				}

				Toggle(
					"Include visible text as context",
					isOn: Binding(
						get: { store.kolSettings.llmScreenContextEnabled },
						set: { store.send(.setLLMScreenContextEnabled($0)) }
					)
				)
				Text("Captures text near the cursor to help recognize technical terms on screen.")
					.font(.system(size: 13))
					.foregroundColor(.secondary)

				if store.kolSettings.llmScreenContextEnabled {
					Toggle(
						"OCR for Electron apps",
						isOn: Binding(
							get: { store.kolSettings.ocrContextEnabled },
							set: { store.send(.setOCRContextEnabled($0)) }
						)
					)
					.padding(.leading, 16)
					Text("Reads screen content via OCR when accessibility text is sparse (Slack, Discord, browser apps).")
						.font(.system(size: 13))
						.foregroundColor(.secondary)
						.padding(.leading, 16)

					if store.kolSettings.ocrContextEnabled {
						HStack(spacing: 6) {
							if screenRecordingPermission == .granted {
								Image(systemName: "checkmark.circle.fill")
									.foregroundStyle(.green)
									.font(.system(size: 13))
								Text("Screen Recording permission granted")
									.font(.system(size: 13))
									.foregroundColor(.secondary)
							} else {
								Image(systemName: "exclamationmark.triangle.fill")
									.foregroundStyle(.yellow)
									.font(.system(size: 13))
								Text("Screen Recording permission required")
									.font(.system(size: 13))
									.foregroundColor(.secondary)
								Button("Grant") {
									store.send(.openScreenRecordingSettings)
								}
								.buttonStyle(.bordered)
								.controlSize(.mini)
							}
						}
						.padding(.leading, 16)
					}
				}

				Toggle(
					"Conversation awareness",
					isOn: Binding(
						get: { store.kolSettings.conversationContextEnabled },
						set: { store.send(.setConversationContextEnabled($0)) }
					)
				)
				Text("Extracts channel names and participant names in messaging and email apps.")
					.font(.system(size: 13))
					.foregroundColor(.secondary)

				if store.kolSettings.conversationContextEnabled {
					Toggle(
						"Auto @-mentions",
						isOn: Binding(
							get: { store.kolSettings.atMentionInsertionEnabled },
							set: { store.send(.setAtMentionInsertionEnabled($0)) }
						)
					)
					.padding(.leading, 16)
					Text("Converts \"at Name\" to \"@Name\" for known participants.")
						.font(.system(size: 13))
						.foregroundColor(.secondary)
						.padding(.leading, 16)
				}

				Toggle(
					"Learn from corrections",
					isOn: Binding(
						get: { store.kolSettings.editTrackingEnabled },
						set: { store.send(.setEditTrackingEnabled($0)) }
					)
				)
				Text("Tracks edits you make after paste to improve future transcriptions.")
					.font(.system(size: 13))
					.foregroundColor(.secondary)

				Button("Customize App Context Prompts...") {
					store.send(.showPromptCustomization)
				}
				.font(.system(size: 13))
			}
			.sheet(
				isPresented: Binding(
					get: { store.showingPromptCustomization },
					set: { if !$0 { store.send(.dismissPromptCustomization) } }
				)
			) {
				PromptCustomizationView(store: store)
			}
		}

		EmptyView()
			.enableInjection()
	}
}
