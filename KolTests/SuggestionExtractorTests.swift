import Foundation
import Testing
@testable import KolCore

@Suite("SuggestionExtractor")
struct SuggestionExtractorTests {
	private func makeTranscript(edits: [WordEdit]) -> Transcript {
		Transcript(
			timestamp: Date(),
			text: "",
			audioPath: URL(fileURLWithPath: "/tmp/test.wav"),
			duration: 1.0,
			wordEdits: edits
		)
	}

	@Test("Empty history returns no suggestions")
	func emptyHistory() {
		let result = SuggestionExtractor.extract(
			from: TranscriptionHistory(),
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.isEmpty)
	}

	@Test("Transcripts without edits return no suggestions")
	func noEdits() {
		let history = TranscriptionHistory(history: [
			Transcript(
				timestamp: Date(),
				text: "hello world",
				audioPath: URL(fileURLWithPath: "/tmp/test.wav"),
				duration: 1.0
			)
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.isEmpty)
	}

	@Test("Single occurrence does not meet threshold")
	func singleOccurrence() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.isEmpty)
	}

	@Test("Two occurrences produce a suggestion")
	func twoOccurrences() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.count == 1)
		#expect(result[0].original == "clawed")
		#expect(result[0].corrected == "Claude")
		#expect(result[0].frequency == 2)
	}

	@Test("Existing remapping is excluded")
	func existingRemappingExcluded() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let existing = [WordRemapping(match: "clawed", replacement: "Claude")]
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: existing,
			dismissedKeys: []
		)
		#expect(result.isEmpty)
	}

	@Test("Dismissed key is excluded")
	func dismissedKeyExcluded() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: ["clawed\u{2192}Claude"]
		)
		#expect(result.isEmpty)
	}

	@Test("Case-insensitive grouping on original word")
	func caseInsensitiveGrouping() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "Clawed", corrected: "Claude", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.count == 1)
		#expect(result[0].frequency == 2)
	}

	@Test("Only substitutions are included")
	func onlySubstitutions() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "hello", corrected: "hello", operation: .match),
				WordEdit(original: "", corrected: "world", operation: .insert),
				WordEdit(original: "foo", corrected: "", operation: .delete),
				WordEdit(original: "claude", corrected: "Claude", operation: .casing)
			]),
			makeTranscript(edits: [
				WordEdit(original: "hello", corrected: "hello", operation: .match),
				WordEdit(original: "", corrected: "world", operation: .insert),
				WordEdit(original: "foo", corrected: "", operation: .delete),
				WordEdit(original: "claude", corrected: "Claude", operation: .casing)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.isEmpty)
	}

	@Test("Sorted by frequency descending, then alphabetically")
	func sortOrder() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "zebra", corrected: "Zebra!", operation: .substitution),
				WordEdit(original: "alpha", corrected: "Alpha!", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "zebra", corrected: "Zebra!", operation: .substitution),
				WordEdit(original: "alpha", corrected: "Alpha!", operation: .substitution),
				WordEdit(original: "alpha", corrected: "Alpha!", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.count == 2)
		#expect(result[0].original == "alpha")  // frequency 3
		#expect(result[0].frequency == 3)
		#expect(result[1].original == "zebra")  // frequency 2
		#expect(result[1].frequency == 2)
	}

	@Test("Custom minimum frequency threshold")
	func customMinimumFrequency() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: [],
			minimumFrequency: 3
		)
		#expect(result.isEmpty)
	}

	@Test("Key format uses Unicode arrow")
	func keyFormat() {
		let suggestion = SuggestedRemapping(original: "clawed", corrected: "Claude", frequency: 2)
		#expect(suggestion.key == "clawed\u{2192}Claude")
		#expect(suggestion.key.contains("→"))
	}

	@Test("Disabled remappings do not exclude suggestions")
	func disabledRemappingDoesNotExclude() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
			])
		])
		let existing = [WordRemapping(isEnabled: false, match: "clawed", replacement: "Claude")]
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: existing,
			dismissedKeys: []
		)
		#expect(result.count == 1)
	}

	@Test("Empty original or corrected words are ignored")
	func emptyWordsIgnored() {
		let history = TranscriptionHistory(history: [
			makeTranscript(edits: [
				WordEdit(original: "", corrected: "Claude", operation: .substitution),
				WordEdit(original: "clawed", corrected: "", operation: .substitution)
			]),
			makeTranscript(edits: [
				WordEdit(original: "", corrected: "Claude", operation: .substitution),
				WordEdit(original: "clawed", corrected: "", operation: .substitution)
			])
		])
		let result = SuggestionExtractor.extract(
			from: history,
			existingRemappings: [],
			dismissedKeys: []
		)
		#expect(result.isEmpty)
	}
}
