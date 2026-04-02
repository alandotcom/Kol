import Testing
@testable import KolCore

@Suite("LLMVocabularyClient.parseResponse")
struct LLMVocabularyClientTests {

	@Test("Parses comma-separated names")
	func commaSeparated() {
		let names = LLMVocabularyClient.parseResponse("Alice, Anthropic, Groq")
		#expect(names == ["Alice", "Anthropic", "Groq"])
	}

	@Test("Returns empty for EMPTY sentinel")
	func emptySentinel() {
		#expect(LLMVocabularyClient.parseResponse("EMPTY") == [])
	}

	@Test("Returns empty for blank string")
	func blankString() {
		#expect(LLMVocabularyClient.parseResponse("") == [])
		#expect(LLMVocabularyClient.parseResponse("  \n  ") == [])
	}

	@Test("Trims whitespace from each name")
	func trimsWhitespace() {
		let names = LLMVocabularyClient.parseResponse("  Alice ,  Bob  , Charlie ")
		#expect(names == ["Alice", "Bob", "Charlie"])
	}

	@Test("Filters out empty items from consecutive commas")
	func emptyItems() {
		let names = LLMVocabularyClient.parseResponse("Alice,,Bob,,,Charlie")
		#expect(names == ["Alice", "Bob", "Charlie"])
	}

	@Test("Filters out items longer than 40 characters")
	func longItems() {
		let long = String(repeating: "A", count: 41)
		let names = LLMVocabularyClient.parseResponse("Alice, \(long), Bob")
		#expect(names == ["Alice", "Bob"])
	}

	@Test("Caps at 140 characters, dropping last partial item")
	func capsAt140() {
		// Build a response that exceeds 140 chars
		let items = (1...20).map { "Name\($0)LongEnough" }
		let response = items.joined(separator: ", ")
		#expect(response.count > 140)
		let names = LLMVocabularyClient.parseResponse(response)
		let rejoined = names.joined(separator: ", ")
		#expect(rejoined.count <= 140)
		#expect(!names.isEmpty)
	}

	@Test("Filters OCR garbage via looksLikeGarbage")
	func garbageFilter() {
		let names = LLMVocabularyClient.parseResponse("Alice, dlscLntiWtbr, Bob")
		#expect(names == ["Alice", "Bob"])
	}

	@Test("Handles single name without comma")
	func singleName() {
		#expect(LLMVocabularyClient.parseResponse("Alice") == ["Alice"])
	}

	@Test("Handles newline-separated names")
	func newlineSeparated() {
		let names = LLMVocabularyClient.parseResponse("Alice\nBob\nCharlie")
		#expect(names == ["Alice", "Bob", "Charlie"])
	}

	@Test("Handles mixed comma and newline separators")
	func mixedSeparators() {
		let names = LLMVocabularyClient.parseResponse("Alice, Bob\nCharlie")
		#expect(names == ["Alice", "Bob", "Charlie"])
	}

	@Test("Handles trailing comma")
	func trailingComma() {
		let names = LLMVocabularyClient.parseResponse("Alice, Bob,")
		#expect(names == ["Alice", "Bob"])
	}

	@Test("Returns empty for EMPTY with surrounding whitespace")
	func emptySentinelWhitespace() {
		#expect(LLMVocabularyClient.parseResponse("  EMPTY  ") == [])
		#expect(LLMVocabularyClient.parseResponse("  EMPTY\n") == [])
	}

	@Test("Preserves numbered list prefixes from LLM output")
	func numberedList() {
		// LLMs sometimes return numbered lists despite the comma-separated instruction.
		// parseResponse does NOT strip numbered prefixes — they pass through as-is.
		let names = LLMVocabularyClient.parseResponse("1. Alice, 2. Bob, 3. Charlie")
		#expect(names == ["1. Alice", "2. Bob", "3. Charlie"])
	}

	@Test("Preserves markdown bold markers from LLM output")
	func markdownFormatting() {
		let names = LLMVocabularyClient.parseResponse("**Alice**, **Bob**")
		#expect(names == ["**Alice**", "**Bob**"])
	}

	@Test("Returns empty for whitespace-only items between commas")
	func whitespaceOnlyItems() {
		#expect(LLMVocabularyClient.parseResponse(" , , , ") == [])
	}

	@Test("Passes through short Hebrew names")
	func hebrewNames() {
		// Short Hebrew names (< 5 chars) bypass the garbage filter.
		// Note: longer Hebrew names may be incorrectly filtered by looksLikeGarbage
		// since its vowel check is Latin-only — that's a VocabularyExtractor concern.
		let names = LLMVocabularyClient.parseResponse("אלן, דני, נועה")
		#expect(names == ["אלן", "דני", "נועה"])
	}

	@Test("Caps at 140 drops no items when response is exactly at limit")
	func exactlyAtCap() {
		// Build a response that's exactly 140 characters
		let item = "NameAB"  // 6 chars
		let separator = ", "  // 2 chars => 8 chars per entry
		// 17 items: 17*6 + 16*2 = 102 + 32 = 134 chars — under cap
		// 18 items: 18*6 + 17*2 = 108 + 34 = 142 chars — over cap
		let items17 = (0..<17).map { _ in item }
		let response17 = items17.joined(separator: separator)
		#expect(response17.count < 140)
		let names17 = LLMVocabularyClient.parseResponse(response17)
		#expect(names17.count == 17)  // No truncation

		let items18 = (0..<18).map { _ in item }
		let response18 = items18.joined(separator: separator)
		#expect(response18.count > 140)
		let names18 = LLMVocabularyClient.parseResponse(response18)
		#expect(names18.count < 18)  // Last partial item dropped
	}
}
