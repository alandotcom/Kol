import Testing
@testable import HexCore

@Suite("PromptAssembler")
struct PromptAssemblerTests {
	@Test("Core rules always present")
	func coreAlwaysPresent() {
		let prompt = PromptAssembler.systemPrompt(language: nil, sourceApp: nil, customRules: nil)
		#expect(prompt.contains("Clean up this speech-to-text"))
		#expect(prompt.contains("Fix punctuation"))
		#expect(prompt.contains("filler words"))
	}

	@Test("Hebrew layer added for Hebrew language")
	func hebrewLayer() {
		let prompt = PromptAssembler.systemPrompt(language: "he", sourceApp: nil, customRules: nil)
		#expect(prompt.contains("maqaf"))
		#expect(prompt.contains("על/אל"))
		#expect(prompt.contains("code-switching"))
	}

	@Test("English layer added for English language")
	func englishLayer() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: nil)
		#expect(prompt.contains("Claude Code"))
		#expect(prompt.contains("camelCase"))
		#expect(!prompt.contains("maqaf"))
	}

	@Test("No language defaults to English layer")
	func nilLanguageDefaultsEnglish() {
		let prompt = PromptAssembler.systemPrompt(language: nil, sourceApp: nil, customRules: nil)
		#expect(prompt.contains("camelCase"))
		#expect(!prompt.contains("maqaf"))
	}

	@Test("Hebrew and English layers are mutually exclusive")
	func languagesExclusive() {
		let he = PromptAssembler.systemPrompt(language: "he", sourceApp: nil, customRules: nil)
		#expect(he.contains("maqaf"))
		#expect(!he.contains("camelCase"))

		let en = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: nil)
		#expect(en.contains("camelCase"))
		#expect(!en.contains("maqaf"))
	}

	@Test("Terminal maps to code context")
	func terminalCodeContext() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "Terminal", customRules: nil)
		#expect(prompt.contains("code editor or terminal"))
		#expect(!prompt.contains("messaging"))
	}

	@Test("VS Code maps to code context")
	func vscodeCodeContext() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "com.microsoft.VSCode", customRules: nil)
		#expect(prompt.contains("code editor or terminal"))
	}

	@Test("iMessage maps to messaging context")
	func imessageMessaging() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "com.apple.MobileSMS", customRules: nil)
		#expect(prompt.contains("messaging app"))
		#expect(!prompt.contains("document or email"))
	}

	@Test("Slack maps to messaging context")
	func slackMessaging() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "Slack", customRules: nil)
		#expect(prompt.contains("messaging app"))
	}

	@Test("Notes maps to document context")
	func notesDocument() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "com.apple.notes", customRules: nil)
		#expect(prompt.contains("document or email"))
		#expect(prompt.contains("bullet points"))
	}

	@Test("Unknown app adds no app context")
	func unknownApp() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "com.random.unknownapp", customRules: nil)
		#expect(!prompt.contains("code editor"))
		#expect(!prompt.contains("messaging"))
		#expect(!prompt.contains("document"))
	}

	@Test("Nil source app adds no app context")
	func nilApp() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: nil)
		#expect(!prompt.contains("code editor"))
		#expect(!prompt.contains("messaging"))
	}

	@Test("Custom rules appended when present")
	func customRulesAppended() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil,
			customRules: "My name is Alan. I work at Fountain Bio."
		)
		#expect(prompt.contains("My name is Alan"))
		#expect(prompt.contains("Fountain Bio"))
		#expect(prompt.contains("Additional context"))
	}

	@Test("Empty custom rules not appended")
	func emptyCustomRules() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: "  \n  ")
		#expect(!prompt.contains("Additional context"))
	}

	@Test("User message is just the text")
	func userMessage() {
		let msg = PromptAssembler.userMessage(text: "hello world")
		#expect(msg == "hello world")
	}

	@Test("Full composition: Hebrew + code + custom")
	func fullComposition() {
		let prompt = PromptAssembler.systemPrompt(
			language: "he",
			sourceApp: "com.apple.Terminal",
			customRules: "My name is אלן"
		)
		// Core
		#expect(prompt.contains("Fix punctuation"))
		// Hebrew
		#expect(prompt.contains("maqaf"))
		// Code
		#expect(prompt.contains("code editor"))
		// Custom
		#expect(prompt.contains("אלן"))
		// Not English
		#expect(!prompt.contains("camelCase"))
	}
}

@Suite("PromptLayers.appContext")
struct PromptLayersAppContextTests {
	@Test("Bundle IDs map correctly")
	func bundleIDs() {
		#expect(PromptLayers.appContext(for: "com.apple.Terminal") != nil)
		#expect(PromptLayers.appContext(for: "com.microsoft.VSCode") != nil)
		#expect(PromptLayers.appContext(for: "com.apple.MobileSMS") != nil)
		#expect(PromptLayers.appContext(for: "com.apple.notes") != nil)
		#expect(PromptLayers.appContext(for: "com.unknown.app") == nil)
		#expect(PromptLayers.appContext(for: nil) == nil)
	}
}
