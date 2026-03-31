import Foundation

/// Pure parsing utilities for extracting person names from text.
/// Used by WindowContextClient to parse AX button descriptions.
public enum NameParser {

	/// Heuristic: does this text look like a person's name?
	/// Accepts single-word names (Alice), multi-word (Alan Cohen), hyphenated (Mary-Jane),
	/// and Unicode letters for non-Western names.
	private static let namePattern: NSRegularExpression = {
		try! NSRegularExpression(pattern: #"^\p{Lu}\p{L}+(?:[\s'\-]\p{L}+)*$"#)
	}()

	public static func looksLikePersonName(_ text: String) -> Bool {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count >= 2, trimmed.count <= 30 else { return false }
		let range = NSRange(trimmed.startIndex..., in: trimmed)
		return namePattern.firstMatch(in: trimmed, range: range) != nil
	}

	/// Parse participant names from Slack-style button descriptions.
	/// Handles patterns like:
	///   "View all 3 members. Includes Joe Cho and Sean Cotter"
	///   "Includes Alice, Bob, Charlie, and Dan"
	///   "Includes Alice and Bob"
	public static func parseNamesFromDescription(_ description: String) -> [String] {
		guard let range = description.range(of: "Includes ", options: .caseInsensitive) else {
			return []
		}

		var tail = String(description[range.upperBound...])
		// Strip trailing period
		if tail.hasSuffix(".") {
			tail = String(tail.dropLast())
		}
		tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !tail.isEmpty else { return [] }

		// Split on ", and " or " and " (Oxford comma or plain)
		// Strategy: replace ", and " and " and " with a common delimiter, then split
		var normalized = tail.replacingOccurrences(of: ", and ", with: "|||")
		normalized = normalized.replacingOccurrences(of: " and ", with: "|||")
		normalized = normalized.replacingOccurrences(of: ", ", with: "|||")

		let candidates = normalized.components(separatedBy: "|||")
		return candidates
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { looksLikePersonName($0) }
	}
}
