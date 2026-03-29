import Testing
@testable import KolCore

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
		#expect(prompt.contains("מאמי"))
		#expect(prompt.contains("NOT ASR errors"))
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

	@Test("Code context includes keyword preservation and operator conversion")
	func codeContextContent() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: "Terminal", customRules: nil)
		#expect(prompt.contains("Programming keywords must stay lowercase exactly as spoken"))
		#expect(prompt.contains("Convert spoken operators to symbols"))
		#expect(prompt.contains("\"equals\" → ="))
		#expect(prompt.contains("match spoken words to identifiers visible on screen"))
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
		// Not English (check for English-only layer content, not code context which also uses camelCase)
		#expect(!prompt.contains("clawed code"))
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

	@Test("Screen context included when provided")
	func screenContextIncluded() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			screenContext: "func resolveModelAndLanguage() {"
		)
		#expect(prompt.contains("currently visible on the user's screen"))
		#expect(prompt.contains("resolveModelAndLanguage"))
	}

	@Test("Screen context uses terminal preamble for terminal apps")
	func screenContextTerminalPreamble() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.mitchellh.ghostty", customRules: nil,
			screenContext: "$ git status"
		)
		#expect(prompt.contains("recent terminal output"))
		#expect(!prompt.contains("currently visible on the user's screen near the cursor"))
		#expect(prompt.contains("git status"))
	}

	@Test("Screen context uses standard preamble for non-terminal apps")
	func screenContextEditorPreamble() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.microsoft.VSCode", customRules: nil,
			screenContext: "func foo() {"
		)
		#expect(prompt.contains("currently visible on the user's screen"))
		#expect(!prompt.contains("recent terminal output"))
	}

	@Test("Screen context excluded when nil")
	func screenContextExcludedNil() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			screenContext: nil
		)
		#expect(!prompt.contains("currently visible"))
	}

	@Test("Empty/whitespace screen context excluded")
	func screenContextExcludedEmpty() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			screenContext: "  \n  "
		)
		#expect(!prompt.contains("currently visible"))
	}

	@Test("Screen context appears between app context and custom rules")
	func screenContextOrdering() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en",
			sourceApp: "Terminal",
			customRules: "My name is Alan",
			screenContext: "let x = 42"
		)
		let appContextRange = prompt.range(of: "code editor or terminal")!
		let screenRange = prompt.range(of: "recent terminal output")!
		let rulesRange = prompt.range(of: "Facts about the speaker")!
		#expect(appContextRange.lowerBound < screenRange.lowerBound)
		#expect(screenRange.lowerBound < rulesRange.lowerBound)
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

@Suite("PromptAssembler helpers")
struct PromptAssemblerHelperTests {
	@Test("extractPrecedingText gets last non-empty line")
	func extractPrecedingText() {
		#expect(PromptAssembler.extractPrecedingText(from: "line1\nline2\nline3") == "line3")
		#expect(PromptAssembler.extractPrecedingText(from: "line1\nline2\n\n") == "line2")
		#expect(PromptAssembler.extractPrecedingText(from: "single line") == "single line")
		#expect(PromptAssembler.extractPrecedingText(from: nil) == nil)
		#expect(PromptAssembler.extractPrecedingText(from: "") == nil)
	}

	@Test("stripPrecedingPrefix removes exact prefix")
	func stripPrecedingPrefix() {
		#expect(PromptAssembler.stripPrecedingPrefix("hello world. How are you?", precedingText: "hello world") == ". How are you?")
		#expect(PromptAssembler.stripPrecedingPrefix("hello world how are you", precedingText: "hello world") == " how are you")
	}

	@Test("stripPrecedingPrefix lowercases after comma join")
	func stripPrecedingPrefixCommaCase() {
		#expect(PromptAssembler.stripPrecedingPrefix("okay, Let's see", precedingText: "okay") == ", let's see")
		#expect(PromptAssembler.stripPrecedingPrefix("okay, let's see", precedingText: "okay") == ", let's see")
	}

	@Test("stripPrecedingPrefix returns original when prefix doesn't match")
	func stripPrecedingPrefixNoMatch() {
		#expect(PromptAssembler.stripPrecedingPrefix("different text", precedingText: "hello world") == "different text")
	}

	@Test("userMessage includes preceding text when provided")
	func userMessageWithPrecedingText() {
		let msg = PromptAssembler.userMessage(text: "how are you", precedingText: "hello")
		#expect(msg.contains("PRECEDING_TEXT: \"hello\""))
		#expect(msg.contains("RAW_TRANSCRIPTION: \"how are you\""))
	}

	@Test("userMessage excludes preceding text when nil")
	func userMessageWithoutPrecedingText() {
		let msg = PromptAssembler.userMessage(text: "hello world", precedingText: nil)
		#expect(!msg.contains("PRECEDING_TEXT"))
		#expect(msg.contains("RAW_TRANSCRIPTION: \"hello world\""))
	}
}

@Suite("PromptLayers.appContextCategory")
struct PromptLayersAppContextTests {
	@Test("Bundle IDs map to correct categories")
	func bundleIDs() {
		#expect(PromptLayers.appContextCategory(for: "com.apple.Terminal") == .code)
		#expect(PromptLayers.appContextCategory(for: "com.microsoft.VSCode") == .code)
		#expect(PromptLayers.appContextCategory(for: "com.mitchellh.ghostty") == .code)
		#expect(PromptLayers.appContextCategory(for: "com.apple.MobileSMS") == .messaging)
		#expect(PromptLayers.appContextCategory(for: "com.apple.notes") == .document)
		#expect(PromptLayers.appContextCategory(for: "com.unknown.app") == nil)
		#expect(PromptLayers.appContextCategory(for: nil) == nil)
	}

	@Test("isTerminal detects terminal emulators")
	func isTerminal() {
		#expect(PromptLayers.isTerminal("com.mitchellh.ghostty"))
		#expect(PromptLayers.isTerminal("com.apple.Terminal"))
		#expect(PromptLayers.isTerminal("com.googlecode.iterm2"))
		#expect(PromptLayers.isTerminal("Ghostty"))
		#expect(PromptLayers.isTerminal("Terminal"))
	}

	@Test("isTerminal rejects non-terminal apps")
	func isNotTerminal() {
		#expect(!PromptLayers.isTerminal("com.microsoft.VSCode"))
		#expect(!PromptLayers.isTerminal("com.apple.dt.xcode"))
		#expect(!PromptLayers.isTerminal("com.apple.notes"))
		#expect(!PromptLayers.isTerminal(nil))
	}
}
