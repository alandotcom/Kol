import Testing
@testable import HexCore

@Suite("PromptAssembler")
struct PromptAssemblerTests {
	@Test("Core rules always present")
	func coreAlwaysPresent() {
		let prompt = PromptAssembler.systemPrompt(language: nil, sourceApp: nil, customRules: nil)
		#expect(prompt.contains("dictation post-processor"))
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
		#expect(prompt.contains("Facts about the speaker"))
	}

	@Test("Empty custom rules not appended")
	func emptyCustomRules() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: "  \n  ")
		#expect(!prompt.contains("Facts about the speaker"))
	}

	@Test("User message is just the text")
	func userMessage() {
		let msg = PromptAssembler.userMessage(text: "hello world")
		#expect(msg == "RAW_TRANSCRIPTION: \"hello world\"")
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

	@Test("App context override replaces default for code apps")
	func codeOverride() {
		let overrides = AppContextOverrides(code: "Custom code instructions here")
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Terminal", customRules: nil,
			appContextOverrides: overrides
		)
		#expect(prompt.contains("Custom code instructions here"))
		#expect(!prompt.contains("code editor or terminal"))
	}

	@Test("App context override replaces default for messaging apps")
	func messagingOverride() {
		let overrides = AppContextOverrides(messaging: "Be super casual")
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			appContextOverrides: overrides
		)
		#expect(prompt.contains("Be super casual"))
		#expect(!prompt.contains("messaging app"))
	}

	@Test("App context override replaces default for document apps")
	func documentOverride() {
		let overrides = AppContextOverrides(document: "Use formal academic tone")
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.apple.notes", customRules: nil,
			appContextOverrides: overrides
		)
		#expect(prompt.contains("Use formal academic tone"))
		#expect(!prompt.contains("document or email"))
	}

	@Test("Nil override uses hardcoded default")
	func nilOverrideUsesDefault() {
		let overrides = AppContextOverrides(code: nil, messaging: nil, document: nil)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Terminal", customRules: nil,
			appContextOverrides: overrides
		)
		#expect(prompt.contains("code editor or terminal"))
	}

	@Test("Empty string override falls back to default")
	func emptyOverrideFallsBack() {
		let overrides = AppContextOverrides(code: "", messaging: "  \n  ", document: nil)
		let codePrompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Terminal", customRules: nil,
			appContextOverrides: overrides
		)
		#expect(codePrompt.contains("code editor or terminal"))

		let msgPrompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			appContextOverrides: overrides
		)
		#expect(msgPrompt.contains("messaging app"))
	}

	@Test("Override does not affect language layers or custom rules")
	func overrideIsolation() {
		let overrides = AppContextOverrides(code: "Custom code prompt")
		let prompt = PromptAssembler.systemPrompt(
			language: "he", sourceApp: "Terminal", customRules: "My name is Test",
			appContextOverrides: overrides
		)
		#expect(prompt.contains("maqaf"))
		#expect(prompt.contains("Custom code prompt"))
		#expect(prompt.contains("My name is Test"))
		#expect(!prompt.contains("camelCase"))
	}
}

@Suite("PromptLayers.appContextCategory")
struct PromptLayersAppContextTests {
	@Test("Bundle IDs map to correct categories")
	func bundleIDs() {
		#expect(PromptLayers.appContextCategory(for: "com.apple.Terminal") == .code)
		#expect(PromptLayers.appContextCategory(for: "com.microsoft.VSCode") == .code)
		#expect(PromptLayers.appContextCategory(for: "com.apple.MobileSMS") == .messaging)
		#expect(PromptLayers.appContextCategory(for: "com.apple.notes") == .document)
		#expect(PromptLayers.appContextCategory(for: "com.unknown.app") == nil)
		#expect(PromptLayers.appContextCategory(for: nil) == nil)
	}
}
