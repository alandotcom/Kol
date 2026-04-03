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

	@Test("Hebrew layer includes no-transliterate rule")
	func hebrewNoTransliterate() {
		let prompt = PromptAssembler.systemPrompt(language: "he", sourceApp: nil, customRules: nil)
		#expect(prompt.contains("output MUST be in Hebrew script"))
		#expect(prompt.contains("Do NOT transliterate Hebrew to Latin characters"))
		#expect(prompt.contains("vocabulary hints or screen context"))
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
		#expect(prompt.contains("Preserve lowercase keywords exactly as spoken"))
		#expect(prompt.contains("Convert spoken punctuation and operators to symbols"))
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
		#expect(prompt.contains("typed into a document"))
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
		#expect(prompt.contains("Background context about the speaker"))
	}

	@Test("Empty custom rules not appended")
	func emptyCustomRules() {
		let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: "  \n  ")
		#expect(!prompt.contains("Background context about the speaker"))
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
		let rulesRange = prompt.range(of: "Background context about the speaker")!
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

	@Test("Structured screen context is included")
	func structuredScreenContextIncluded() {
		let ctx = CursorContext(
			beforeCursor: "let x = ",
			afterCursor: "\nprint(x)",
			selectedText: nil,
			isTerminal: false
		)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.apple.dt.Xcode",
			customRules: nil, structuredContext: ctx
		)
		#expect(prompt.contains("--- BEFORE CURSOR ---"))
		#expect(prompt.contains("--- AFTER CURSOR ---"))
	}

	@Test("Structured context takes precedence over flat screenContext")
	func structuredContextPrecedence() {
		let ctx = CursorContext(
			beforeCursor: "structured",
			afterCursor: "content",
			selectedText: nil,
			isTerminal: false
		)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			screenContext: "flat text",
			structuredContext: ctx
		)
		#expect(prompt.contains("--- BEFORE CURSOR ---"))
		#expect(!prompt.contains("flat text"))
	}

	@Test("Fallback to flat screenContext when structuredContext is nil")
	func fallbackToFlatScreenContext() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			screenContext: "some visible text",
			structuredContext: nil
		)
		#expect(prompt.contains("some visible text"))
	}

	@Test("Fallback to flat screenContext when structuredContext has empty flatText")
	func fallbackWhenStructuredContextEmpty() {
		let ctx = CursorContext(
			beforeCursor: "",
			afterCursor: "",
			selectedText: nil,
			isTerminal: false
		)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			screenContext: "fallback text",
			structuredContext: ctx
		)
		#expect(prompt.contains("fallback text"))
	}

	@Test("Terminal preamble in structured context")
	func structuredContextTerminalPreamble() {
		let ctx = CursorContext(
			beforeCursor: "$ git status",
			afterCursor: "",
			selectedText: nil,
			isTerminal: true
		)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			structuredContext: ctx
		)
		#expect(prompt.contains("terminal output"))
	}

	@Test("Vocabulary hints included")
	func vocabularyHintsIncluded() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			vocabularyHints: ["handleStartRecording", "CursorContext"]
		)
		#expect(prompt.contains("handleStartRecording"))
		#expect(prompt.contains("CursorContext"))
		#expect(prompt.contains("Names and identifiers visible on screen"))
	}

	@Test("Empty vocabulary hints array excluded")
	func vocabularyHintsEmptyExcluded() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil, customRules: nil,
			vocabularyHints: []
		)
		#expect(!prompt.contains("Names and identifiers"))
	}

	@Test("Ordering: structuredContext before vocabularyHints before customRules")
	func structuredContextVocabCustomRulesOrdering() {
		let ctx = CursorContext(
			beforeCursor: "let x = 42",
			afterCursor: "",
			selectedText: nil,
			isTerminal: false
		)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: nil,
			customRules: "My name is Alan",
			structuredContext: ctx,
			vocabularyHints: ["handleStartRecording"]
		)
		let structuredRange = prompt.range(of: "--- BEFORE CURSOR ---")!
		let vocabRange = prompt.range(of: "Names and identifiers visible on screen")!
		let rulesRange = prompt.range(of: "Background context about the speaker")!
		#expect(structuredRange.lowerBound < vocabRange.lowerBound)
		#expect(vocabRange.lowerBound < rulesRange.lowerBound)
	}

	// MARK: - IDE Context Tests

	@Test("IDE context included when provided for code app")
	func ideContextIncluded() {
		let ide = IDEContext(openFileNames: ["TranscriptionFeature.swift", "AppDelegate.swift"])
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.microsoft.VSCode", customRules: nil,
			ideContext: ide
		)
		#expect(prompt.contains("Open files:"))
		#expect(prompt.contains("TranscriptionFeature.swift"))
		#expect(prompt.contains("AppDelegate.swift"))
		#expect(prompt.contains("Language: Swift"))
	}

	@Test("IDE context excluded when nil")
	func ideContextExcludedNil() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.microsoft.VSCode", customRules: nil,
			ideContext: nil
		)
		#expect(!prompt.contains("Open files:"))
	}

	@Test("IDE context excluded when openFileNames is empty")
	func ideContextExcludedEmpty() {
		let ide = IDEContext(openFileNames: [])
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.microsoft.VSCode", customRules: nil,
			ideContext: ide
		)
		#expect(!prompt.contains("Open files:"))
	}

	@Test("IDE context ordering: between app context and screen context")
	func ideContextOrdering() {
		let ide = IDEContext(openFileNames: ["App.swift"])
		let ctx = CursorContext(
			beforeCursor: "let x = 42",
			afterCursor: "",
			selectedText: nil,
			isTerminal: false
		)
		let prompt = PromptAssembler.systemPrompt(
			language: "en",
			sourceApp: "Terminal",
			customRules: "My name is Alan",
			ideContext: ide,
			structuredContext: ctx,
			vocabularyHints: ["someIdentifier"]
		)
		let appContextRange = prompt.range(of: "code editor or terminal")!
		let ideRange = prompt.range(of: "Open files:")!
		let screenRange = prompt.range(of: "--- BEFORE CURSOR ---")!
		let vocabRange = prompt.range(of: "Names and identifiers visible on screen")!
		let rulesRange = prompt.range(of: "Background context about the speaker")!
		#expect(appContextRange.lowerBound < ideRange.lowerBound)
		#expect(ideRange.lowerBound < screenRange.lowerBound)
		#expect(screenRange.lowerBound < vocabRange.lowerBound)
		#expect(vocabRange.lowerBound < rulesRange.lowerBound)
	}

	// MARK: - Anti-Rephrase Rule

	@Test("Core prompt includes anti-rephrase rule")
	func antiRephraseRule() {
		let prompt = PromptAssembler.systemPrompt(language: nil, sourceApp: nil, customRules: nil)
		#expect(prompt.contains("never rephrase, restructure, or reword"))
		#expect(prompt.contains("Keep the speaker's original sentence structure"))
	}

	// MARK: - Conversation Context

	@Test("Conversation context included when provided")
	func conversationContextIncluded() {
		let convo = ConversationContext(conversationName: "#engineering")
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			conversationContext: convo
		)
		#expect(prompt.contains("Conversation: #engineering"))
	}

	@Test("Conversation context excluded when nil")
	func conversationContextNil() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			conversationContext: nil
		)
		#expect(!prompt.contains("Conversation:"))
	}

	@Test("Conversation context excluded when no name")
	func conversationContextEmpty() {
		let convo = ConversationContext(conversationName: nil)
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			conversationContext: convo
		)
		#expect(!prompt.contains("Conversation:"))
	}

	@Test("Conversation context excluded when name is empty string")
	func conversationContextEmptyString() {
		let convo = ConversationContext(conversationName: "")
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			conversationContext: convo
		)
		#expect(!prompt.contains("Conversation:"))
	}

	@Test("Conversation context appears after app context and before screen context")
	func conversationContextOrdering() {
		let convo = ConversationContext(conversationName: "#test")
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			screenContext: "some visible text",
			conversationContext: convo
		)
		let messagingIdx = prompt.range(of: "messaging app")!.lowerBound
		let convoIdx = prompt.range(of: "Conversation: #test")!.lowerBound
		let screenIdx = prompt.range(of: "visible on the user's screen")!.lowerBound
		#expect(messagingIdx < convoIdx)
		#expect(convoIdx < screenIdx)
	}

	// MARK: - @-mention Instruction

	@Test("@-mention instruction included when enabled")
	func atMentionEnabled() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			atMentionEnabled: true
		)
		#expect(prompt.contains("@-mention"))
		#expect(prompt.contains("@Alice"))
	}

	@Test("@-mention instruction excluded when disabled")
	func atMentionDisabled() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			atMentionEnabled: false
		)
		#expect(!prompt.contains("@-mention"))
	}

	@Test("@-mention instruction appears after screen context and before vocabulary hints")
	func atMentionOrdering() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "Slack", customRules: nil,
			screenContext: "Alice Johnson\nHello",
			vocabularyHints: ["handleFoo"],
			atMentionEnabled: true
		)
		let screenIdx = prompt.range(of: "visible on the user's screen")!.lowerBound
		let mentionIdx = prompt.range(of: "@-mention")!.lowerBound
		let vocabIdx = prompt.range(of: "Names and identifiers visible on screen")!.lowerBound
		#expect(screenIdx < mentionIdx)
		#expect(mentionIdx < vocabIdx)
	}

	// MARK: - Email App Context

	@Test("Email app gets email-specific prompt")
	func emailAppContext() {
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.apple.mail", customRules: nil
		)
		#expect(prompt.contains("email"))
		#expect(prompt.contains("trailing periods"))
		#expect(!prompt.contains("messaging app"))
	}

	// MARK: - Resolved Category Override

	@Test("Resolved category overrides bundle ID detection")
	func resolvedCategoryOverride() {
		// Chrome with a Gmail URL should get email context, not unknown
		let prompt = PromptAssembler.systemPrompt(
			language: "en", sourceApp: "com.google.Chrome", customRules: nil,
			resolvedCategory: .email
		)
		#expect(prompt.contains("email"))
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
		#expect(PromptLayers.appContextCategory(for: "com.apple.mail") == .email)
		#expect(PromptLayers.appContextCategory(for: "com.google.Gmail") == .email)
		#expect(PromptLayers.appContextCategory(for: "com.unknown.app") == nil)
		#expect(PromptLayers.appContextCategory(for: nil) == nil)
	}

	@Test("Email apps are distinct from document apps")
	func emailVsDocument() {
		#expect(PromptLayers.appContextCategory(for: "com.apple.mail") == .email)
		#expect(PromptLayers.appContextCategory(for: "com.apple.notes") == .document)
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
