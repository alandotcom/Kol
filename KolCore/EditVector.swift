import Foundation

/// A single word-level edit operation detected between pasted and edited text.
public struct WordEdit: Codable, Equatable, Sendable {
	public let original: String
	public let corrected: String
	public let operation: EditOperation

	public init(original: String, corrected: String, operation: EditOperation) {
		self.original = original
		self.corrected = corrected
		self.operation = operation
	}
}

/// Types of word-level edit operations.
public enum EditOperation: String, Codable, Sendable {
	case match = "M"
	case substitution = "S"
	case insert = "I"
	case delete = "D"
	case casing = "C"
}

/// Computes word-level edit vectors between original (pasted) and edited text.
/// Uses Wagner-Fischer edit distance on word arrays, with a casing-only detection post-pass.
public enum EditVectorComputer {
	/// Compute the edit vector and detailed word edits between original and edited text.
	/// Returns a vector string (e.g., "MMSMM") and the list of individual word edits.
	public static func compute(original: String, edited: String) -> (vector: String, edits: [WordEdit]) {
		let origWords = words(from: original)
		let editWords = words(from: edited)

		guard !origWords.isEmpty || !editWords.isEmpty else {
			return ("", [])
		}

		let m = origWords.count
		let n = editWords.count

		// Wagner-Fischer DP table
		var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
		for i in 0...m { dp[i][0] = i }
		for j in 0...n { dp[0][j] = j }

		for i in 1...m {
			for j in 1...n {
				if origWords[i - 1].lowercased() == editWords[j - 1].lowercased() {
					// Case-insensitive match (may be exact or casing-only change)
					dp[i][j] = dp[i - 1][j - 1]
				} else {
					dp[i][j] = min(
						dp[i - 1][j] + 1,     // delete
						dp[i][j - 1] + 1,     // insert
						dp[i - 1][j - 1] + 1  // substitute
					)
				}
			}
		}

		// Backtrace to build alignment
		var edits: [WordEdit] = []
		var i = m, j = n

		while i > 0 || j > 0 {
			if i > 0 && j > 0 && origWords[i - 1].lowercased() == editWords[j - 1].lowercased() {
				// Case-insensitive match
				let op: EditOperation = (origWords[i - 1] == editWords[j - 1]) ? .match : .casing
				edits.append(WordEdit(original: origWords[i - 1], corrected: editWords[j - 1], operation: op))
				i -= 1; j -= 1
			} else if i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1 {
				// Substitution
				edits.append(WordEdit(original: origWords[i - 1], corrected: editWords[j - 1], operation: .substitution))
				i -= 1; j -= 1
			} else if j > 0 && dp[i][j] == dp[i][j - 1] + 1 {
				// Insertion
				edits.append(WordEdit(original: "", corrected: editWords[j - 1], operation: .insert))
				j -= 1
			} else if i > 0 && dp[i][j] == dp[i - 1][j] + 1 {
				// Deletion
				edits.append(WordEdit(original: origWords[i - 1], corrected: "", operation: .delete))
				i -= 1
			} else {
				break // shouldn't happen
			}
		}

		edits.reverse()

		let vector = edits.map(\.operation.rawValue).joined()
		return (vector, edits)
	}

	private static func words(from text: String) -> [String] {
		text.split(whereSeparator: \.isWhitespace).map(String.init)
	}
}
