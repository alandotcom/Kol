import Foundation

/// Rewrites "at [Name]" patterns to "@Name" when the name matches a known participant.
/// Case-insensitive "at" trigger, case-preserving name output.
public enum AtMentionRewriter {
	/// Rewrite "at [Name]" patterns in the text to "@Name" for known participants.
	/// Only rewrites when the word after "at" matches a known name (case-insensitive).
	public static func rewrite(_ text: String, knownNames: [String]) -> String {
		guard !knownNames.isEmpty else { return text }

		var result = text
		for name in knownNames {
			// Match "at Name" or "At Name" (case-insensitive "at", exact name match)
			// Use word boundaries to avoid matching inside other words
			let escapedName = NSRegularExpression.escapedPattern(for: name)
			guard let regex = try? NSRegularExpression(
				pattern: #"\b[Aa]t\s+"# + escapedName + #"\b"#
			) else { continue }

			let range = NSRange(result.startIndex..., in: result)
			result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "@\(name)")
		}

		return result
	}
}
