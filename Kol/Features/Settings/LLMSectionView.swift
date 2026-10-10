import ComposableArchitecture
import SwiftUI

struct LLMSectionContent: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Toggle("Enable AI post-processing", isOn: Binding(
            get: { store.kolSettings.llmPostProcessingEnabled },
            set: { store.send(.setLLMEnabled($0)) }
        ))
        if store.kolSettings.llmPostProcessingEnabled {
            Picker("Provider", selection: Binding(
                get: { store.kolSettings.llmProviderPreset },
                set: { store.send(.setLLMPreset($0)) }
            )) {
                ForEach(LLMProviderPreset.allCases, id: \.rawValue) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            SecureField("API key", text: Binding(
                get: { store.llmApiKey },
                set: { store.send(.setLLMApiKey($0)) }
            ))
            .disabled(!store.isLLMApiKeyLoaded)
            Text("API keys are stored in macOS Keychain.").settingsCaption()
            let isCustom = store.kolSettings.llmProviderPreset == LLMProviderPreset.custom.rawValue
            TextField("Base URL", text: Binding(
                get: { store.kolSettings.llmProviderBaseURL },
                set: { store.send(.setLLMBaseURL($0)) }
            ))
            .disabled(!isCustom)
            if store.kolSettings.llmProviderPreset == LLMProviderPreset.openrouter.rawValue {
                LabeledContent("Model") {
                    Button(store.kolSettings.llmModelName.isEmpty ? "Choose model…" : store.kolSettings.llmModelName) {
                        store.send(.showOpenRouterModels)
                    }
                    .lineLimit(1)
                    .sheet(isPresented: Binding(
                        get: { store.showingOpenRouterModels },
                        set: { if !$0 { store.send(.dismissOpenRouterModels) } }
                    )) {
                        OpenRouterModelPickerView(
                            store: store.scope(state: \.openRouterModels, action: \.openRouterModels),
                            dismiss: { store.send(.dismissOpenRouterModels) }
                        )
                    }
                }
                if store.kolSettings.llmModelName.isEmpty {
                    Text("Choose a model to use OpenRouter post-processing.").settingsCaption()
                }
            } else {
                TextField("Model", text: Binding(
                    get: { store.kolSettings.llmModelName },
                    set: { store.send(.setLLMModelName($0)) }
                ))
                .disabled(!isCustom)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom context")
                TextEditor(text: Binding(
                    get: { store.kolSettings.llmCustomRules },
                    set: { store.send(.setLLMCustomRules($0)) }
                ))
                .frame(height: 90)
                .accessibilityLabel("Custom context")
                Text("Add your preferred names, terminology, or formatting rules.").settingsCaption()
                if !store.kolSettings.llmCustomRules.isEmpty {
                    Button("Clear custom context") { store.send(.setLLMCustomRules("")) }
                }
            }
            Button("Customize app context prompts…") { store.send(.showPromptCustomization) }
                .sheet(isPresented: Binding(
                    get: { store.showingPromptCustomization },
                    set: { if !$0 { store.send(.dismissPromptCustomization) } }
                )) { PromptCustomizationView(store: store) }
        }
    }
}

struct ContextPrivacySettingsContent: View {
    @Bindable var store: StoreOf<SettingsFeature>
    let screenRecordingPermission: PermissionStatus

    var body: some View {
        Toggle("Include visible text as context", isOn: Binding(
            get: { store.kolSettings.llmScreenContextEnabled },
            set: { store.send(.setLLMScreenContextEnabled($0)) }
        ))
        Text("Reads text near the cursor to recognize names and technical terms. When AI post-processing is enabled, context is included in provider requests.")
            .settingsCaption()
        if store.kolSettings.llmScreenContextEnabled {
            Toggle("Read screen text with OCR", isOn: Binding(
                get: { store.kolSettings.ocrContextEnabled },
                set: { store.send(.setOCRContextEnabled($0)) }
            ))
            Text("Uses screen capture when an app provides little accessibility text.").settingsCaption()
            if store.kolSettings.ocrContextEnabled {
                LabeledContent("Screen Recording") {
                    if screenRecordingPermission == .granted {
                        Label("Allowed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") { store.send(.openScreenRecordingSettings) }
                            .accessibilityLabel("Allow Screen Recording")
                    }
                }
            }
            Toggle("Include conversation context", isOn: Binding(
                get: { store.kolSettings.conversationContextEnabled },
                set: { store.send(.setConversationContextEnabled($0)) }
            ))
            Text("Reads conversation and channel information in messaging and email apps.").settingsCaption()
            if store.kolSettings.conversationContextEnabled {
                Toggle("Insert @-mentions", isOn: Binding(
                    get: { store.kolSettings.atMentionInsertionEnabled },
                    set: { store.send(.setAtMentionInsertionEnabled($0)) }
                ))
                Text("Converts spoken mentions into @-mentions for names visible on screen.").settingsCaption()
            }
        }
    }
}
