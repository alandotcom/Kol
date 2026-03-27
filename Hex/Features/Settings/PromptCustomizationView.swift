import ComposableArchitecture
import HexCore
import SwiftUI

struct PromptCustomizationView: View {
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("App Context Prompts")
				.font(.headline)

			Text("Customize the instructions sent to the LLM for each type of app. These tell the AI how to format and clean up your transcription.")
				.font(.caption)
				.foregroundStyle(.secondary)

			promptEditor(
				title: "Code Editor / Terminal",
				caption: "Terminal, VS Code, Xcode, Cursor, Zed, IntelliJ, Sublime...",
				value: store.hexSettings.llmPromptCode,
				defaultText: PromptLayers.appContextCode,
				onSet: { store.send(.setLLMPromptCode($0)) },
				onReset: { store.send(.setLLMPromptCode(nil)) }
			)

			promptEditor(
				title: "Messaging",
				caption: "Messages, Slack, WhatsApp, Telegram, Discord...",
				value: store.hexSettings.llmPromptMessaging,
				defaultText: PromptLayers.appContextMessaging,
				onSet: { store.send(.setLLMPromptMessaging($0)) },
				onReset: { store.send(.setLLMPromptMessaging(nil)) }
			)

			promptEditor(
				title: "Documents / Email",
				caption: "Mail, Notes, Notion, Word, Pages, Bear...",
				value: store.hexSettings.llmPromptDocument,
				defaultText: PromptLayers.appContextDocument,
				onSet: { store.send(.setLLMPromptDocument($0)) },
				onReset: { store.send(.setLLMPromptDocument(nil)) }
			)

			Spacer()

			HStack {
				Spacer()
				Button("Done") {
					store.send(.dismissPromptCustomization)
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 480, height: 520)
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
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(title)
					.font(.subheadline)
					.fontWeight(.medium)
				if value != nil {
					Text("(customized)")
						.font(.caption2)
						.foregroundStyle(.blue)
				}
				Spacer()
				if value != nil {
					Button("Reset to Default") { onReset() }
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
			.frame(height: 60)
			.font(.caption)
			.scrollContentBackground(.hidden)
			.background(Color(.textBackgroundColor).opacity(0.5))
			.clipShape(.rect(cornerRadius: 6))

			Text(caption)
				.font(.caption2)
				.foregroundStyle(.tertiary)
		}
	}
}
