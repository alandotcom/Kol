import ComposableArchitecture
import KolCore
import SwiftUI

struct PromptCustomizationView: View {
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		VStack(alignment: .leading, spacing: 24) {
			VStack(alignment: .leading, spacing: 8) {
				Text("App Context Prompts")
					.font(.title3.weight(.semibold))

				Text("Customize the instructions sent to the LLM for each type of app. These tell the AI how to format and clean up your transcription.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}

			ScrollView {
				VStack(spacing: 20) {
					promptEditor(
						title: "Code Editor / Terminal",
						caption: "Terminal, VS Code, Xcode, Cursor, Zed, IntelliJ, Sublime...",
						value: store.kolSettings.llmPromptCode,
						defaultText: PromptLayers.appContextCode,
						onSet: { store.send(.setLLMPromptCode($0)) },
						onReset: { store.send(.setLLMPromptCode(nil)) }
					)

					promptEditor(
						title: "Messaging",
						caption: "Messages, Slack, WhatsApp, Telegram, Discord...",
						value: store.kolSettings.llmPromptMessaging,
						defaultText: PromptLayers.appContextMessaging,
						onSet: { store.send(.setLLMPromptMessaging($0)) },
						onReset: { store.send(.setLLMPromptMessaging(nil)) }
					)

					promptEditor(
						title: "Documents / Email",
						caption: "Mail, Notes, Notion, Word, Pages, Bear...",
						value: store.kolSettings.llmPromptDocument,
						defaultText: PromptLayers.appContextDocument,
						onSet: { store.send(.setLLMPromptDocument($0)) },
						onReset: { store.send(.setLLMPromptDocument(nil)) }
					)
				}
			}

			HStack {
				Spacer()
				Button("Done") {
					store.send(.dismissPromptCustomization)
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
				.controlSize(.regular)
			}
		}
		.padding(28)
		.frame(width: 560, height: 580)
	}

	@ViewBuilder
	private func promptEditor(
		title: String,
		caption: String,
		value: String?,
		defaultText: String,
		onSet: @escaping (String) -> Void,
		onReset: @escaping () -> Void
	) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline) {
				Text(title)
					.font(.subheadline.weight(.semibold))
				if value != nil {
					Text("customized")
						.font(.caption)
						.foregroundStyle(.blue)
						.padding(.horizontal, 8)
						.padding(.vertical, 2)
						.background(Color.blue.opacity(0.1))
						.clipShape(Capsule())
				}
				Spacer()
				if value != nil {
					Button("Reset") { onReset() }
						.font(.caption)
						.buttonStyle(.plain)
						.foregroundStyle(.secondary)
				}
			}

			TextEditor(
				text: Binding(
					get: { value ?? defaultText },
					set: { onSet($0) }
				)
			)
			.frame(height: 80)
			.font(.system(.caption, design: .monospaced))
			.scrollContentBackground(.hidden)
			.padding(10)
			.background(GlassColors.dropdownBackground)
			.clipShape(RoundedRectangle(cornerRadius: 10))
			.overlay(
				RoundedRectangle(cornerRadius: 10)
					.strokeBorder(GlassColors.dropdownBorder, lineWidth: 0.5)
			)

			Text(caption)
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
	}
}
