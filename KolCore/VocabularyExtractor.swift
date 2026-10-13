import Foundation

private let logger = KolLog.vocabulary

/// Extracts proper nouns, code identifiers, and file or folder names from screen text.
/// All extraction is local (no network), runs synchronously, and is designed for ~3000 char inputs.
public enum VocabularyExtractor {
	public struct Result: Sendable, Equatable {
		public let properNouns: [String]
		public let identifiers: [String]
		public let fileNames: [String]
		public let pathTerms: [String]

		public init(properNouns: [String], identifiers: [String], fileNames: [String], pathTerms: [String] = []) {
			self.properNouns = properNouns
			self.identifiers = identifiers
			self.fileNames = fileNames
			self.pathTerms = pathTerms
		}

		/// All terms combined, deduplicated, capped at `maxTerms`. Names come first, then path
		/// spellings, so a crowded vocabulary drops plain identifiers before either.
		public var allTerms: [String] {
			var seen = Set<String>()
			var terms: [String] = []
			for term in properNouns + pathTerms + identifiers + fileNames {
				let key = term.lowercased()
				if seen.insert(key).inserted {
					terms.append(term)
				}
			}
			return Array(terms.prefix(maxTerms))
		}
	}

	public static let maxTerms = 50

	/// Dictionary lookup supplied by the app (the system spell checker). Words it does not know,
	/// such as product, project and person names ("Knip", "Hasnack"), are kept as vocabulary
	/// wherever they appear. Nil leaves dictionary-based extraction off, as in tests that do
	/// not set it.
	nonisolated(unsafe) public static var isKnownWord: ((String) -> Bool)?

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

	private static let kebabCaseRegex = try! NSRegularExpression(
		pattern: #"\b[a-z][a-z0-9]*(?:-[a-z][a-z0-9]*)+\b"#
	)

	/// A single product name followed by a dotted release version.
	private static let versionedNameRegex = try! NSRegularExpression(
		pattern: #"\b([A-Z][a-zA-Z]{2,})[ \t]+v?\d+(?:\.\d+){2,}\b(?!\.\d)"#
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

	/// Contiguous relative paths, including extensionless folders. Excludes URL fragments.
	private static let pathRegex = try! NSRegularExpression(
		pattern: #"(?<![\w.:/\\-])(?:\./)?(\.?[\p{L}_][\p{L}\p{N}_-]*(?:\.[\p{L}\p{N}_-]+)*(?:/\.?[\p{L}_][\p{L}\p{N}_-]*(?:\.[\p{L}\p{N}_-]+)*)+)(?![\w/\\-])"#
	)

	private static let slashPhrases: Set<String> = ["and/or", "read/write", "input/output", "yes/no", "on/off", "true/false"]

	/// Maximum input length for extraction. Screen text beyond this threshold
	/// adds diminishing returns for vocabulary quality but increases regex cost.
	private static let maxInputLength = 2000

	public static func extract(from text: String, isKnownWord: ((String) -> Bool)? = VocabularyExtractor.isKnownWord) -> Result {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return Result(properNouns: [], identifiers: [], fileNames: [])
		}

		// Truncate to cap regex work — called every 1s during recording
		let input = text.count > maxInputLength ? String(text.prefix(maxInputLength)) : text

		let identifiers = extractIdentifiers(from: input).filter { !looksLikeGarbage($0) }
		let properNouns = extractProperNouns(from: input, isKnownWord: isKnownWord).filter { !looksLikeGarbage($0) }
		let fileNames = extractFileNames(from: input)
		let pathTerms = extractPathTerms(from: input)

		let result = Result(
			properNouns: properNouns,
			identifiers: identifiers,
			fileNames: fileNames,
			pathTerms: pathTerms
		)
		let termsPreview = result.allTerms.joined(separator: ", ")
		logger.info("Extracted \(result.allTerms.count) terms [\(termsPreview)]: \(identifiers.count) identifiers, \(properNouns.count) nouns, \(fileNames.count) files")
		return result
	}

	// MARK: - Identifier Extraction

	/// Matches camelCase, PascalCase, snake_case, and kebab-case identifiers.
	private static func extractIdentifiers(from text: String) -> [String] {
		var results: [String] = []
		var seen = Set<String>()

		let range = NSRange(text.startIndex..., in: text)
		for regex in [camelCaseRegex, pascalCaseRegex, snakeCaseRegex, kebabCaseRegex] {
			for match in regex.matches(in: text, range: range) {
				if let matchRange = Range(match.range, in: text) {
					let term = String(text[matchRange])
					if term.count >= 3, seen.insert(term).inserted {
						results.append(term)
					}
				}
			}
		}

		for match in versionedNameRegex.matches(in: text, range: range) {
			guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
			let name = String(text[nameRange])
			guard !["version", "release", "build"].contains(name.lowercased()) else { continue }
			if let labelRange = Range(match.range, in: text) {
				let label = String(text[labelRange])
				if seen.insert(label).inserted { results.append(label) }
			}
			if seen.insert(name).inserted { results.append(name) }
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
	/// e.g., "Carlos Mendes", "Claude Code", "Example Labs"
	private static func extractProperNouns(from text: String, isKnownWord: ((String) -> Bool)?) -> [String] {
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

		for name in extractSingleWordNames(from: text) + extractUnknownWords(from: text, isKnownWord: isKnownWord) where seen.insert(name.lowercased()).inserted {
			results.append(name)
		}
		return results
	}

	private static let plainWordRegex = try! NSRegularExpression(pattern: #"(?<![\w./-])(?:[A-Z][a-zA-Z]{2,}|[a-z]{4,})(?![\w/-])"#)

	/// Words of four or more letters that the dictionary does not know, kept in their on-screen
	/// casing. Words inside identifiers, paths or file names are skipped; those have their own
	/// extractors.
	private static func extractUnknownWords(from text: String, isKnownWord: ((String) -> Bool)?) -> [String] {
		guard let isKnownWord else { return [] }
		let found = plainWordRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
		var occurrences: [String: Int] = [:]
		for word in found { occurrences[word.lowercased(), default: 0] += 1 }
		var results: [String] = []
		var seen = Set<String>()
		for word in found {
			let key = word.lowercased()
			guard seen.insert(key).inserted, !looksLikeGarbage(word), !isKnownWord(key) else { continue }
			if word.first?.isUppercase != true {
				// Lowercase unknown words are mostly text-recognition noise: neighboring words read
				// as one ("the he" as "thehe"). Keep one only if it repeats and does not split into
				// two dictionary words. Capitalized names are kept on first sight.
				let letters = Array(key)
				let isMerge = letters.count >= 4 && (2...(letters.count - 2)).contains { cut in
					isKnownWord(String(letters[..<cut])) && isKnownWord(String(letters[cut...]))
				}
				guard occurrences[key, default: 0] >= 2, !isMerge else { continue }
			}
			results.append(word)
		}
		return results
	}

	private static let singleWordRegex = try! NSRegularExpression(pattern: #"\b[A-Z][a-z]{2,}\b"#)
	private static let anyWordRegex = try! NSRegularExpression(pattern: #"\b[A-Za-z]+\b"#)

	/// Finds one-word names such as app, product or person names ("Kol", "Zed", "Yuki").
	///
	/// A capitalized word counts when it appears capitalized at least twice in mid-sentence
	/// positions (after a lowercase word or a comma on the same line) and never appears in
	/// lowercase anywhere in the text. Ordinary words capitalized once by UI labels or sentence
	/// starts ("Welcome", "Settings") fail one of these checks; a name the user is working with
	/// tends to repeat with the same capitalization.
	private static func extractSingleWordNames(from text: String) -> [String] {
		let range = NSRange(text.startIndex..., in: text)
		var lowercaseWords = Set<String>()
		for match in anyWordRegex.matches(in: text, range: range) {
			guard let wordRange = Range(match.range, in: text) else { continue }
			let word = String(text[wordRange])
			if word == word.lowercased() { lowercaseWords.insert(word) }
		}
		var counts: [String: Int] = [:]
		var order: [String] = []
		for match in singleWordRegex.matches(in: text, range: range) {
			guard let wordRange = Range(match.range, in: text) else { continue }
			let before = text[..<wordRange.lowerBound]
			// Mid-sentence: the nearest earlier character on the same line is a space preceded by
			// a lowercase letter, a digit or a comma.
			guard before.last == " ", let previous = before.dropLast().last,
				  previous.isLowercase || previous.isNumber || previous == "," else { continue }
			let word = String(text[wordRange])
			guard !lowercaseWords.contains(word.lowercased()) else { continue }
			if counts[word] == nil { order.append(word) }
			counts[word, default: 0] += 1
		}
		return order.filter { counts[$0, default: 0] >= 2 && !looksLikeGarbage($0) }
	}

	// MARK: - Path Extraction

	private static func extractPathTerms(from text: String) -> [String] {
		let range = NSRange(text.startIndex..., in: text)
		var terms: [String] = []
		for match in pathRegex.matches(in: text, range: range) {
			guard let pathRange = Range(match.range(at: 1), in: text) else { continue }
			let path = String(text[pathRange])
			guard !slashPhrases.contains(path.lowercased()) else { continue }
			let components = path.split(separator: "/").map(String.init)
			guard !components.contains(where: looksLikeGarbage) else { continue }
			if !looksLikeHash(path) { terms.append(path) }
			terms.append(contentsOf: components.filter { $0.count >= 3 && !looksLikeHash($0) })
		}
		return terms
	}

	/// True for fragments that contain a run of six or more hexadecimal characters including a
	/// digit, such as hashes and UUID pieces in temporary paths.
	static func looksLikeHash(_ term: String) -> Bool {
		term.range(of: #"(?=[0-9a-fA-F]*[0-9])[0-9a-fA-F]{6,}"#, options: .regularExpression) != nil
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
		//    like "SearchHarbor" where "rchH" spans a word boundary.
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
