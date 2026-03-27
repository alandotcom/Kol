import Foundation

// MARK: - Post-Processing Context

/// Everything the LLM needs to clean up a transcription.
/// The caller assembles this; the client handles prompt composition internally.
public struct PostProcessingContext: Sendable {
	public let text: String
	public let inputLanguage: String?
	public let sourceApp: String?
	public let customRules: String?
	public let appContextOverrides: AppContextOverrides?

	public init(
		text: String,
		inputLanguage: String? = nil,
		sourceApp: String? = nil,
		customRules: String? = nil,
		appContextOverrides: AppContextOverrides? = nil
	) {
		self.text = text
		self.inputLanguage = inputLanguage
		self.sourceApp = sourceApp
		self.customRules = customRules
		self.appContextOverrides = appContextOverrides
	}
}

// MARK: - Provider Config

/// Connection config for any OpenAI-compatible API.
public struct LLMProviderConfig: Codable, Equatable, Sendable {
	public var baseURL: String
	public var modelName: String

	public init(baseURL: String, modelName: String) {
		self.baseURL = baseURL
		self.modelName = modelName
	}
}

/// Known fast inference providers.
public enum LLMProviderPreset: String, CaseIterable, Codable, Sendable {
	case groq
	case cerebras
	case custom

	public var displayName: String {
		switch self {
		case .groq: return "Groq"
		case .cerebras: return "Cerebras"
		case .custom: return "Custom"
		}
	}

	public var defaultConfig: LLMProviderConfig {
		switch self {
		case .groq:
			return LLMProviderConfig(
				baseURL: "https://api.groq.com/openai/v1",
				modelName: "meta-llama/llama-4-scout-17b-16e-instruct"
			)
		case .cerebras:
			return LLMProviderConfig(
				baseURL: "https://api.cerebras.ai/v1",
				modelName: "llama-4-scout-17b-16e"
			)
		case .custom:
			return LLMProviderConfig(baseURL: "", modelName: "")
		}
	}
}

// MARK: - App Context

/// Category of app for prompt context selection.
public enum AppContextCategory: String, Sendable, Equatable {
	case code
	case messaging
	case document
}

/// User overrides for the built-in app context prompt layers.
/// When a field is nil, the hardcoded default is used.
public struct AppContextOverrides: Sendable {
	public let code: String?
	public let messaging: String?
	public let document: String?

	public init(code: String? = nil, messaging: String? = nil, document: String? = nil) {
		self.code = code
		self.messaging = messaging
		self.document = document
	}

	/// Returns the override for a given category, or nil if unset or empty.
	public func text(for category: AppContextCategory) -> String? {
		let value: String? = switch category {
		case .code: code
		case .messaging: messaging
		case .document: document
		}
		guard let v = value, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
		return v
	}
}

// MARK: - Prompt Layers

/// Independent prompt fragments, each covering one concern.
/// Composed by `PromptAssembler` — not concatenated by callers.
public enum PromptLayers {
	public static let core = """
	You are a text post-processor. You receive raw speech-to-text output and return ONLY the cleaned version. \
	Fix punctuation (periods, commas, question marks). \
	Remove filler words (um, uh, like, you know). \
	Fix obvious ASR misrecognitions. \
	Do NOT change meaning, translate, summarize, or add commentary. \
	Do NOT include any preamble, explanation, or acknowledgment. \
	Do NOT say "here is" or "sure" or anything similar. \
	Your entire response must be the cleaned transcription text and nothing else.
	"""

	public static let hebrew = """
	Hebrew-specific rules: \
	Use maqaf (־) for Hebrew compound words. \
	Preserve natural Hebrew-English code-switching — do not translate between languages. \
	Fix ambiguous short words based on context (על/אל, אם/עם, לא/לו). \
	Remove Hebrew filler words (אממ, אהה, ככה, אז אה).
	"""

	public static let english = """
	English-specific rules: \
	Fix common tech ASR errors (e.g. "clawed code" → "Claude Code", "next js" → "Next.js", "react" → "React", "typescript" → "TypeScript"). \
	Preserve camelCase, PascalCase, and technical terms.
	"""

	public static let appContextCode = """
	The text is being typed into a code editor or terminal. \
	Keep technical terms exact. Do not add bullet points or decorative formatting. Preserve casing.
	"""

	public static let appContextMessaging = """
	The text will be pasted into a messaging app. \
	Do not formalize the tone. Do not add bullet points or structured formatting.
	"""

	public static let appContextDocument = """
	The text is being typed into a document or email. \
	Use proper formatting. Format enumerated items as bullet points.
	"""

	/// Identifies which app context category an app belongs to.
	/// Returns nil for unknown apps.
	public static func appContextCategory(for appIdentifier: String?) -> AppContextCategory? {
		guard let app = appIdentifier?.lowercased() else { return nil }

		let codeApps = [
			"terminal", "iterm", "warp", "alacritty", "kitty", "ghostty",
			"vscode", "visual studio code", "code", "xcode", "neovim", "vim",
			"intellij", "webstorm", "pycharm", "cursor", "zed", "sublime",
			"com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable",
			"com.microsoft.vscode", "com.apple.dt.xcode", "com.todesktop.230313mzl4w4u92",
			"dev.zed.zed",
		]
		let messagingApps = [
			"messages", "imessage", "slack", "whatsapp", "telegram", "discord",
			"com.apple.mobilesms", "com.tinyspeck.slackmacgap",
			"net.whatsapp.whatsapp", "ru.keepcoder.telegram",
			"com.hnc.discord",
		]
		let documentApps = [
			"mail", "notion", "google docs", "pages", "word", "notes", "bear",
			"com.apple.mail", "notion.id", "com.apple.notes",
			"com.microsoft.word", "com.apple.iwork.pages",
		]

		if codeApps.contains(where: { app.contains($0) }) { return .code }
		if messagingApps.contains(where: { app.contains($0) }) { return .messaging }
		if documentApps.contains(where: { app.contains($0) }) { return .document }
		return nil
	}

	/// Returns the default prompt text for a given category.
	public static func defaultText(for category: AppContextCategory) -> String {
		switch category {
		case .code: return appContextCode
		case .messaging: return appContextMessaging
		case .document: return appContextDocument
		}
	}
}

// MARK: - Prompt Assembler

/// Composes a system prompt from independent layers based on context.
/// Callers provide context; the assembler decides which layers to include.
public enum PromptAssembler {
	/// Build the system prompt by composing applicable layers.
	/// - Parameters:
	///   - language: Detected language code (e.g. "he", "en")
	///   - sourceApp: App name or bundle ID of the frontmost app
	///   - customRules: User-provided context/facts
	///   - appContextOverrides: Optional per-category prompt text overrides
	public static func systemPrompt(
		language: String?,
		sourceApp: String?,
		customRules: String?,
		appContextOverrides: AppContextOverrides? = nil
	) -> String {
		var parts: [String] = [PromptLayers.core]

		if let lang = language?.lowercased() {
			if lang.hasPrefix("he") {
				parts.append(PromptLayers.hebrew)
			} else if lang.hasPrefix("en") {
				parts.append(PromptLayers.english)
			}
		} else {
			// No language specified — include both since we don't know
			parts.append(PromptLayers.english)
		}

		if let category = PromptLayers.appContextCategory(for: sourceApp) {
			let text = appContextOverrides?.text(for: category) ?? PromptLayers.defaultText(for: category)
			parts.append(text)
		}

		if let rules = customRules, !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			parts.append("Facts about the speaker (use to correct ASR errors, do not mention these in output):\n\(rules)")
		}

		return parts.joined(separator: "\n\n")
	}

	/// Build the user message. Just the transcription text — all instructions go in the system prompt.
	public static func userMessage(text: String) -> String {
		text
	}
}
