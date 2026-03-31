import Testing
@testable import KolCore

@Suite("VocabularyExtractor")
struct VocabularyExtractorTests {

	// MARK: - camelCase

	@Test("Extracts camelCase identifiers")
	func camelCase() {
		let result = VocabularyExtractor.extract(from: "call handleStartRecording and capturedScreenContext")
		#expect(result.identifiers.contains("handleStartRecording"))
		#expect(result.identifiers.contains("capturedScreenContext"))
	}

	// MARK: - PascalCase

	@Test("Extracts PascalCase identifiers")
	func pascalCase() {
		let result = VocabularyExtractor.extract(from: "class ScreenContextClient extends TranscriptionFeature")
		#expect(result.identifiers.contains("ScreenContextClient"))
		#expect(result.identifiers.contains("TranscriptionFeature"))
	}

	// MARK: - snake_case

	@Test("Extracts snake_case identifiers")
	func snakeCase() {
		let result = VocabularyExtractor.extract(from: "let source_app_bundle_id = max_context_length")
		#expect(result.identifiers.contains("source_app_bundle_id"))
		#expect(result.identifiers.contains("max_context_length"))
	}

	// MARK: - Proper Nouns

	@Test("Extracts multi-word proper nouns")
	func properNouns() {
		let result = VocabularyExtractor.extract(from: "Talk to Alan Cohen about Claude Code at Fountain Bio")
		#expect(result.properNouns.contains("Alan Cohen"))
		#expect(result.properNouns.contains("Claude Code"))
		#expect(result.properNouns.contains("Fountain Bio"))
	}

	@Test("Does not extract single capitalized words as proper nouns")
	func singleCapitalizedWord() {
		let result = VocabularyExtractor.extract(from: "Hello world Welcome back")
		#expect(result.properNouns.isEmpty)
	}

	// MARK: - File Names

	@Test("Extracts file names with known extensions")
	func fileNames() {
		let result = VocabularyExtractor.extract(from: "Open AppFeature.swift and package.json")
		#expect(result.fileNames.contains("AppFeature.swift"))
		#expect(result.fileNames.contains("package.json"))
	}

	@Test("Ignores files with unknown extensions")
	func unknownExtensions() {
		let result = VocabularyExtractor.extract(from: "Download report.xlsx and photo.jpeg")
		#expect(result.fileNames.isEmpty)
	}

	// MARK: - Deduplication

	@Test("Deduplicates across categories")
	func dedup() {
		// "AppFeature" matches both PascalCase identifier and could appear as proper noun
		let result = VocabularyExtractor.extract(from: "AppFeature AppFeature AppFeature")
		let allTerms = result.allTerms
		let count = allTerms.filter { $0 == "AppFeature" }.count
		#expect(count == 1)
	}

	// MARK: - Cap

	@Test("Caps at maxTerms")
	func maxTermsCap() {
		// Generate a string with many identifiers
		let identifiers = (1...60).map { "identifier\($0)Value" }.joined(separator: " ")
		let result = VocabularyExtractor.extract(from: identifiers)
		#expect(result.allTerms.count <= VocabularyExtractor.maxTerms)
	}

	// MARK: - Edge Cases

	@Test("Returns empty for empty input")
	func emptyInput() {
		let result = VocabularyExtractor.extract(from: "")
		#expect(result.allTerms.isEmpty)
	}

	@Test("Returns empty for whitespace input")
	func whitespaceInput() {
		let result = VocabularyExtractor.extract(from: "   \n\t  ")
		#expect(result.allTerms.isEmpty)
	}

	@Test("Does not extract short identifiers")
	func shortIdentifiers() {
		// "ab" has length 2, should be filtered
		let result = VocabularyExtractor.extract(from: "the aB is tiny")
		#expect(result.identifiers.isEmpty)
	}

	@Test("allTerms combines all categories")
	func allTermsCombines() {
		let result = VocabularyExtractor.extract(from: "handleStart by Alan Cohen in AppFeature.swift")
		let all = result.allTerms
		// Should contain identifier, proper noun, and file name
		#expect(all.contains("Alan Cohen"))
		#expect(all.contains("AppFeature.swift"))
	}

	// MARK: - OCR Garbage Filter

	@Test("Rejects OCR garbage with low vowel ratio")
	func rejectsLowVowels() {
		#expect(VocabularyExtractor.looksLikeGarbage("dlscLntrWt"))
		#expect(VocabularyExtractor.looksLikeGarbage("bLrtxm"))
	}

	@Test("Rejects OCR garbage with long consonant runs")
	func rejectsConsonantRuns() {
		#expect(VocabularyExtractor.looksLikeGarbage("IrnplerrwtstiDn"))
		#expect(VocabularyExtractor.looksLikeGarbage("sSedxmblrt"))
	}

	@Test("Accepts valid names")
	func acceptsValidNames() {
		#expect(!VocabularyExtractor.looksLikeGarbage("Jane Smith"))
		#expect(!VocabularyExtractor.looksLikeGarbage("Michael Chen"))
		#expect(!VocabularyExtractor.looksLikeGarbage("Maria Rodriguez"))
		#expect(!VocabularyExtractor.looksLikeGarbage("David Kim"))
	}

	@Test("Accepts valid identifiers")
	func acceptsValidIdentifiers() {
		#expect(!VocabularyExtractor.looksLikeGarbage("handleStart"))
		#expect(!VocabularyExtractor.looksLikeGarbage("SearchEngine"))
		#expect(!VocabularyExtractor.looksLikeGarbage("viewModel"))
	}

	@Test("Accepts short terms without filtering")
	func acceptsShortTerms() {
		#expect(!VocabularyExtractor.looksLikeGarbage("Liz"))
		#expect(!VocabularyExtractor.looksLikeGarbage("Bio"))
		#expect(!VocabularyExtractor.looksLikeGarbage("App"))
	}

	@Test("Filters garbage from extract results")
	func extractFiltersGarbage() {
		let text = "IrnplerrwtstiDn dlscLntrWt Jane Smith handleStart"
		let result = VocabularyExtractor.extract(from: text)
		#expect(!result.allTerms.contains("IrnplerrwtstiDn"))
		#expect(!result.allTerms.contains("dlscLntrWt"))
		#expect(result.allTerms.contains("Jane Smith"))
	}
}
