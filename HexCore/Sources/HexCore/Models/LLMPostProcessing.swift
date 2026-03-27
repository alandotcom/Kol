import Foundation

// MARK: - Post-Processing Context

/// Everything the LLM needs to clean up a transcription.
/// The caller assembles this; the client handles prompt composition internally.
public struct PostProcessingContext: Sendable {
	public let text: String
	public let inputLanguage: String?
	public let sourceApp: String?
	public let customRules: String?

	public init(
		text: String,
		inputLanguage: String? = nil,
		sourceApp: String? = nil,
		customRules: String? = nil
	) {
		self.text = text
		self.inputLanguage = inputLanguage
		self.sourceApp = sourceApp
		self.customRules = customRules
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

// MARK: - Prompt Layers

/// Independent prompt fragments, each covering one concern.
/// Composed by `PromptAssembler` — not concatenated by callers.
public enum PromptLayers {
	public static let core = """
	Clean up this speech-to-text transcription. \
	Fix punctuation (periods, commas, question marks). \
	Remove filler words (um, uh, like, you know). \
	Fix obvious ASR misrecognitions. \
	Do NOT change meaning, translate, summarize, or add commentary. \
	Output ONLY the cleaned text.
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
	The text is being typed into a messaging app. \
	Keep the tone casual and conversational. Do not add bullet points.
	"""

	public static let appContextDocument = """
	The text is being typed into a document or email. \
	Use proper formatting. Format enumerated items as bullet points.
	"""

	/// Maps an app name or bundle ID to the appropriate context layer.
	/// Returns nil for unknown apps (core rules only).
	public static func appContext(for appIdentifier: String?) -> String? {
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

		if codeApps.contains(where: { app.contains($0) }) {
			return appContextCode
		}
		if messagingApps.contains(where: { app.contains($0) }) {
			return appContextMessaging
		}
		if documentApps.contains(where: { app.contains($0) }) {
			return appContextDocument
		}
		return nil
	}
}

// MARK: - Prompt Assembler

/// Composes a system prompt from independent layers based on context.
/// Callers provide context; the assembler decides which layers to include.
public enum PromptAssembler {
	/// Build the system prompt by composing applicable layers.
	public static func systemPrompt(
		language: String?,
		sourceApp: String?,
		customRules: String?
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

		if let appLayer = PromptLayers.appContext(for: sourceApp) {
			parts.append(appLayer)
		}

		if let rules = customRules, !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			parts.append("Additional context from the user:\n\(rules)")
		}

		return parts.joined(separator: "\n\n")
	}

	/// Build the user message. Just the transcription text — all instructions go in the system prompt.
	public static func userMessage(text: String) -> String {
		text
	}
}
