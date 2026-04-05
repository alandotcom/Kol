import Foundation

private let logger = KolLog.vocabulary

/// Extracts proper nouns, code identifiers, and file names from screen text using regex patterns.
/// All extraction is local (no network), runs synchronously, and is designed for ~3000 char inputs.
public enum VocabularyExtractor {
	public struct Result: Sendable, Equatable {
		public let properNouns: [String]
		public let identifiers: [String]
		public let fileNames: [String]

		public init(properNouns: [String], identifiers: [String], fileNames: [String]) {
			self.properNouns = properNouns
			self.identifiers = identifiers
			self.fileNames = fileNames
		}

		/// All terms combined, deduplicated, capped at `maxTerms`.
		public var allTerms: [String] {
			var seen = Set<String>()
			var terms: [String] = []
			for term in identifiers + properNouns + fileNames {
				let key = term.lowercased()
				if seen.insert(key).inserted {
					terms.append(term)
				}
			}
			return Array(terms.prefix(maxTerms))
		}
	}

	public static let maxTerms = 50

	/// Known source code file extensions for filtering file name matches.
	private static let knownExtensions: Set<String> = [
		"swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java",
		"kt", "c", "cpp", "h", "hpp", "m", "mm", "cs", "json", "yaml",
		"yml", "toml", "xml", "html", "css", "scss", "md", "txt", "sh",
		"zsh", "fish", "sql", "graphql", "proto", "vue", "svelte",
	]

	// MARK: - Precompiled Regex Patterns

	/// camelCase: starts lowercase, has at least one uppercase transition
	/// e.g., handleStartRecording, capturedScreenContext
	private static let camelCaseRegex = try! NSRegularExpression(
		pattern: #"\b[a-z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)+\b"#
	)

	/// PascalCase: starts uppercase, has at least one additional uppercase transition
	/// e.g., ScreenContextClient, TranscriptionFeature
	private static let pascalCaseRegex = try! NSRegularExpression(
		pattern: #"\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+\b"#
	)

	/// snake_case: lowercase with underscores
	/// e.g., source_app_bundle_id, max_context_length
	private static let snakeCaseRegex = try! NSRegularExpression(
		pattern: #"\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b"#
	)

	/// Sequences of capitalized words (2+ words, same line only).
	/// Uses `[ \t]+` instead of `\s+` to avoid matching across OCR line breaks,
	/// which would stitch unrelated sidebar words into garbage "proper nouns".
	private static let properNounRegex = try! NSRegularExpression(
		pattern: #"\b[A-Z][a-z]+(?:[ \t]+[A-Z][a-z]+)+\b"#
	)


	/// File names with known extensions
	/// e.g., "AppFeature.swift", "package.json", "README.md"
	private static let fileNameRegex = try! NSRegularExpression(
		pattern: #"\b[\w][\w.-]*\.(\w{1,5})\b"#
	)

	/// Maximum input length for extraction. Screen text beyond this threshold
	/// adds diminishing returns for vocabulary quality but increases regex cost.
	private static let maxInputLength = 2000

	public static func extract(from text: String) -> Result {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return Result(properNouns: [], identifiers: [], fileNames: [])
		}

		// Truncate to cap regex work — called every 1s during recording
		let input = text.count > maxInputLength ? String(text.prefix(maxInputLength)) : text

		let identifiers = extractIdentifiers(from: input).filter { !looksLikeGarbage($0) }
		let properNouns = extractProperNouns(from: input).filter { !looksLikeGarbage($0) }
		let fileNames = extractFileNames(from: input)

		let result = Result(
			properNouns: properNouns,
			identifiers: identifiers,
			fileNames: fileNames
		)
		let termsPreview = result.allTerms.joined(separator: ", ")
		logger.info("Extracted \(result.allTerms.count) terms [\(termsPreview)]: \(identifiers.count) identifiers, \(properNouns.count) nouns, \(fileNames.count) files")
		return result
	}

	// MARK: - Identifier Extraction

	/// Matches camelCase, PascalCase, and snake_case identifiers.
	private static func extractIdentifiers(from text: String) -> [String] {
		var results: [String] = []
		var seen = Set<String>()

		let range = NSRange(text.startIndex..., in: text)
		for regex in [camelCaseRegex, pascalCaseRegex, snakeCaseRegex] {
			for match in regex.matches(in: text, range: range) {
				if let matchRange = Range(match.range, in: text) {
					let term = String(text[matchRange])
					if term.count >= 3, seen.insert(term).inserted {
						results.append(term)
					}
				}
			}
		}

		return results
	}

	// MARK: - Proper Noun Extraction

	/// Common UI/navigation phrases that OCR picks up from sidebars and chrome across apps.
	/// These are never useful as vocabulary hints for transcription correction.
	private static let uiStopwords: Set<String> = [
		// Messaging sidebars
		"all chats", "archived chats", "direct messages", "all dms", "group chats",
		"all channels", "all messages", "pinned messages", "saved messages",
		"starred messages", "unread messages", "new message", "new chat",
		// Slack-specific
		"all unreads", "mention reactions", "slack connect",
		// Email
		"sent mail", "all mail", "important messages", "junk mail",
		// Navigation / buttons
		"read more", "read less", "see more", "see all", "show more", "show less",
		"learn more", "view all", "load more", "go back", "get started",
		"sign in", "sign up", "log in", "log out", "read only",
		// macOS
		"system settings", "system preferences",
		// Time
		"last week", "last month", "this week", "this month",
	]

	/// Matches sequences of capitalized words (2+ words).
	/// e.g., "Alan Cohen", "Claude Code", "Fountain Bio"
	private static func extractProperNouns(from text: String) -> [String] {
		let range = NSRange(text.startIndex..., in: text)
		var results: [String] = []
		var seen = Set<String>()

		for match in properNounRegex.matches(in: text, range: range) {
			if let matchRange = Range(match.range, in: text) {
				let term = String(text[matchRange])
				let key = term.lowercased()
				// Filter: skip common UI/navigation phrases
				if uiStopwords.contains(key) { continue }
				// Filter: skip if it looks like a sentence start (preceded by ". " or start of line)
				let startIdx = matchRange.lowerBound
				if startIdx > text.startIndex {
					let prevIdx = text.index(before: startIdx)
					let prevChar = text[prevIdx]
					// If preceded by period+space, likely sentence start — skip
					if prevChar == " " && prevIdx > text.startIndex {
						let prevPrevIdx = text.index(before: prevIdx)
						if text[prevPrevIdx] == "." {
							continue
						}
					}
				}
				if seen.insert(key).inserted {
					results.append(term)
				}
			}
		}

		return results
	}

	// MARK: - File Name Extraction

	/// Matches file names with known extensions.
	/// e.g., "AppFeature.swift", "package.json", "README.md"
	private static func extractFileNames(from text: String) -> [String] {
		let range = NSRange(text.startIndex..., in: text)
		var results: [String] = []
		var seen = Set<String>()

		for match in fileNameRegex.matches(in: text, range: range) {
			guard let fullRange = Range(match.range, in: text),
				  let extRange = Range(match.range(at: 1), in: text)
			else { continue }

			let ext = String(text[extRange]).lowercased()
			guard knownExtensions.contains(ext) else { continue }

			let fileName = String(text[fullRange])
			if seen.insert(fileName.lowercased()).inserted {
				results.append(fileName)
			}
		}

		return results
	}

	// MARK: - OCR Garbage Filter

	private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "A", "E", "I", "O", "U"]

	/// Rejects terms that look like OCR misreads rather than real words.
	/// OCR garbage characteristics: low vowel ratio, long consonant runs, digit-letter mixing.
	static func looksLikeGarbage(_ term: String) -> Bool {
		// Split multi-word terms and check each word
		let words = term.split(separator: " ")
		for word in words {
			if wordLooksLikeGarbage(String(word)) { return true }
		}
		return false
	}

	private static func wordLooksLikeGarbage(_ word: String) -> Bool {
		guard word.count >= 5 else { return false }

		let letters = word.filter(\.isLetter)
		guard letters.count >= 5 else { return false }

		// 1. Vowel ratio: reject if < 15% vowels (most languages need ~25%+)
		let vowelCount = letters.filter { vowels.contains($0) }.count
		let vowelRatio = Double(vowelCount) / Double(letters.count)
		if vowelRatio < 0.15 { return true }

		// 2. Consecutive consonants: 5+ non-vowel lowercase letters in a row
		//    Reset on uppercase (PascalCase boundaries) to avoid false positives
		//    like "SearchFountain" where "rchF" spans a word boundary.
		var consonantRun = 0
		for char in word where char.isLetter {
			if vowels.contains(char) || char.isUppercase {
				consonantRun = 0
			} else {
				consonantRun += 1
				if consonantRun >= 5 { return true }
			}
		}

		return false
	}
}
