import Foundation

/// A suggested word remapping derived from recurring user corrections.
public struct SuggestedRemapping: Equatable, Sendable, Identifiable {
	public var id: String { key }
	public let original: String
	public let corrected: String
	public let frequency: Int

	/// Stable key for dismissed-tracking: "original→corrected"
	public var key: String { "\(original)\u{2192}\(corrected)" }

	public init(original: String, corrected: String, frequency: Int) {
		self.original = original
		self.corrected = corrected
		self.frequency = frequency
	}
}

/// Scans transcription history for recurring word corrections and suggests remappings.
public enum SuggestionExtractor {
	/// Extract suggested remappings from transcription history.
	///
	/// Finds single-word substitutions that recur across transcripts.
	/// Excludes suggestions that already exist as remappings or have been dismissed.
	public static func extract(
		from history: TranscriptionHistory,
		existingRemappings: [WordRemapping],
		dismissedKeys: [String],
		minimumFrequency: Int = 2
	) -> [SuggestedRemapping] {
		// Build frequency table: "original_lowered→corrected" -> (original, corrected, count)
		var frequencies: [String: (original: String, corrected: String, count: Int)] = [:]

		for transcript in history.history {
			guard let edits = transcript.wordEdits else { continue }
			for edit in edits where edit.operation == .substitution {
				let original = edit.original
				let corrected = edit.corrected
				guard !original.isEmpty, !corrected.isEmpty else { continue }

				let key = "\(original.lowercased())\u{2192}\(corrected)"
				if let existing = frequencies[key] {
					frequencies[key] = (existing.original, existing.corrected, existing.count + 1)
				} else {
					frequencies[key] = (original, corrected, 1)
				}
			}
		}

		let dismissedSet = Set(dismissedKeys)
		let existingSet = Set(existingRemappings.filter(\.isEnabled).map {
			"\($0.match.lowercased())\u{2192}\($0.replacement)"
		})

		return frequencies.values
			.filter { $0.count >= minimumFrequency }
			.map { SuggestedRemapping(original: $0.original, corrected: $0.corrected, frequency: $0.count) }
			.filter { !dismissedSet.contains($0.key) }
			.filter { !existingSet.contains("\($0.original.lowercased())\u{2192}\($0.corrected)") }
			.sorted { lhs, rhs in
				if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
				return lhs.original.lowercased() < rhs.original.lowercased()
			}
	}
}
