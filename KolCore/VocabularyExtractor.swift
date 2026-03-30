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

	public static func extract(from text: String) -> Result {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return Result(properNouns: [], identifiers: [], fileNames: [])
		}

		let identifiers = extractIdentifiers(from: text)
		let properNouns = extractProperNouns(from: text)
		let fileNames = extractFileNames(from: text)

		let result = Result(
			properNouns: properNouns,
			identifiers: identifiers,
			fileNames: fileNames
		)
		logger.debug("Extracted \(result.allTerms.count) terms: \(identifiers.count) identifiers, \(properNouns.count) nouns, \(fileNames.count) files")
		return result
	}

	// MARK: - Identifier Extraction

	/// Matches camelCase, PascalCase, and snake_case identifiers.
	private static func extractIdentifiers(from text: String) -> [String] {
		var results: [String] = []
		var seen = Set<String>()

		// camelCase: starts lowercase, has at least one uppercase transition
		// e.g., handleStartRecording, capturedScreenContext
		let camelCase = try! NSRegularExpression(
			pattern: #"\b[a-z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)+\b"#
		)

		// PascalCase: starts uppercase, has at least one additional uppercase transition
		// e.g., ScreenContextClient, TranscriptionFeature
		let pascalCase = try! NSRegularExpression(
			pattern: #"\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+\b"#
		)

		// snake_case: lowercase with underscores
		// e.g., source_app_bundle_id, max_context_length
		let snakeCase = try! NSRegularExpression(
			pattern: #"\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b"#
		)

		let range = NSRange(text.startIndex..., in: text)
		for regex in [camelCase, pascalCase, snakeCase] {
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

	/// Matches sequences of capitalized words (2+ words).
	/// e.g., "Alan Cohen", "Claude Code", "Fountain Bio"
	private static func extractProperNouns(from text: String) -> [String] {
		let pattern = try! NSRegularExpression(
			pattern: #"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b"#
		)
		let range = NSRange(text.startIndex..., in: text)
		var results: [String] = []
		var seen = Set<String>()

		for match in pattern.matches(in: text, range: range) {
			if let matchRange = Range(match.range, in: text) {
				let term = String(text[matchRange])
				let key = term.lowercased()
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
		let pattern = try! NSRegularExpression(
			pattern: #"\b[\w][\w.-]*\.(\w{1,5})\b"#
		)
		let range = NSRange(text.startIndex..., in: text)
		var results: [String] = []
		var seen = Set<String>()

		for match in pattern.matches(in: text, range: range) {
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
}
