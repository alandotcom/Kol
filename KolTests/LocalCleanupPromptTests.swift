import Dependencies
import Foundation
import Testing
@testable import KolCore

struct LocalCleanupPromptTests {
    @Test func serializesTrainingSchemaAndChatTemplate() throws {
        let context = PostProcessingContext(text: "check fern buffer slash api", ideContext: IDEContext(openFileNames: ["Router.swift"]), focusedText: FocusedText(value: "FernBuffer"), vocabularyHints: ["FernBuffer"], resolvedCategory: .code)
        let text = try LocalCleanupPrompt.userMessage(context)
        let value = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(value["category"] as? String == "code")
        #expect(value["vocabulary"] as? [String] == ["FernBuffer"])
        #expect(value["language"] as? String == "en")
        #expect(value["mentions_enabled"] as? Bool == false)
        #expect(Set(value.keys) == ["text", "category", "focused", "vocabulary", "mentions_enabled", "ide", "conversation_name", "custom_rules", "language"])
        #expect(try LocalCleanupPrompt.chatText(context) == "<|im_start|>system\n" + LocalCleanupPrompt.system + "<|im_end|>\n<|im_start|>user\n" + text + "<|im_end|>\n<|im_start|>assistant\n")
    }

    @Test func localClientBypassesRemoteRequest() async throws {
        let result = try await withDependencies {
            $0.localCleanup.process = { context in
                LLMProcessingResult(text: "Cleaned text.", metadata: LLMMetadata(originalText: context.text, model: "local"))
            }
        } operation: {
            try await LLMPostProcessingClient.liveValue.process(PostProcessingContext(text: "raw text"), LLMProviderPreset.local.defaultConfig, "")
        }
        #expect(result.text == "Cleaned text.")
        #expect(result.metadata.model == "local")
    }

    @Test func localProviderDoesNotRequireRemoteConfiguration() {
        let config = LLMProviderPreset.local.defaultConfig
        #expect(config.isLocal)
        #expect(config.baseURL.isEmpty)
        #expect(!LLMProviderPreset.groq.defaultConfig.isLocal)
    }
}
