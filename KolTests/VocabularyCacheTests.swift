import Testing
@testable import KolCore

@Suite("VocabularyCacheClient")
struct VocabularyCacheTests {

	private func makeLiveCache() -> VocabularyCacheClient {
		VocabularyCacheClient.liveValue
	}

	@Test("Merge adds terms and topTerms returns them")
	func mergeAndRetrieve() {
		let cache = makeLiveCache()
		let vocab = VocabularyExtractor.Result(
			properNouns: ["Alan Cohen"],
			identifiers: ["handleStartRecording"],
			fileNames: ["AppFeature.swift"]
		)
		cache.merge(vocab)
		let terms = cache.topTerms(10)
		#expect(terms.contains("handleStartRecording"))
		#expect(terms.contains("Alan Cohen"))
		#expect(terms.contains("AppFeature.swift"))
	}

	@Test("Multiple merges increment counts — most frequent first")
	func frequencyOrdering() {
		let cache = makeLiveCache()

		// Merge "frequent" term twice, "rare" term once
		let vocab1 = VocabularyExtractor.Result(
			properNouns: [], identifiers: ["frequentTerm", "rareTerm"], fileNames: []
		)
		cache.merge(vocab1)

		let vocab2 = VocabularyExtractor.Result(
			properNouns: [], identifiers: ["frequentTerm"], fileNames: []
		)
		cache.merge(vocab2)

		let terms = cache.topTerms(10)
		guard let freqIdx = terms.firstIndex(of: "frequentTerm"),
			  let rareIdx = terms.firstIndex(of: "rareTerm") else {
			Issue.record("Expected both terms in cache")
			return
		}
		#expect(freqIdx < rareIdx)
	}

	@Test("topTerms respects limit")
	func topTermsLimit() {
		let cache = makeLiveCache()
		let vocab = VocabularyExtractor.Result(
			properNouns: ["Alpha Beta", "Gamma Delta"],
			identifiers: ["identOne", "identTwo", "identThree"],
			fileNames: []
		)
		cache.merge(vocab)
		let terms = cache.topTerms(2)
		#expect(terms.count == 2)
	}

	@Test("Clear empties the cache")
	func clearCache() {
		let cache = makeLiveCache()
		let vocab = VocabularyExtractor.Result(
			properNouns: ["Alan Cohen"], identifiers: [], fileNames: []
		)
		cache.merge(vocab)
		#expect(!cache.topTerms(10).isEmpty)

		cache.clear()
		#expect(cache.topTerms(10).isEmpty)
	}

	@Test("Deduplicates case-insensitively, preserves original form")
	func caseInsensitiveDedup() {
		let cache = makeLiveCache()
		let vocab1 = VocabularyExtractor.Result(
			properNouns: [], identifiers: ["MyTerm"], fileNames: []
		)
		cache.merge(vocab1)

		// Same term, different case — should increment, not add duplicate
		let vocab2 = VocabularyExtractor.Result(
			properNouns: [], identifiers: ["myterm"], fileNames: []
		)
		cache.merge(vocab2)

		let terms = cache.topTerms(10)
		// Should have only one entry (original form preserved)
		#expect(terms.count == 1)
		#expect(terms.first == "MyTerm")
	}

	@Test("Eviction enforces maxEntries and retains most recent terms")
	func evictionEnforcesMaxEntries() {
		let cache = makeLiveCache()
		let maxEntries = VocabularyCacheClient.maxEntries  // 200

		// Merge old terms first — one per merge so each gets a distinct lastSeen timestamp
		let oldTermCount = maxEntries
		for i in 0..<oldTermCount {
			let vocab = VocabularyExtractor.Result(
				properNouns: [], identifiers: ["old_\(i)"], fileNames: []
			)
			cache.merge(vocab)
		}

		// Now merge 10 new terms in a single batch — they are the most recent
		let newTerms = (0..<10).map { "new_\($0)" }
		let newVocab = VocabularyExtractor.Result(
			properNouns: [], identifiers: newTerms, fileNames: []
		)
		cache.merge(newVocab)

		// Should be capped at maxEntries
		let terms = cache.topTerms(300)
		#expect(terms.count == maxEntries)

		// All 10 new terms should be retained (most recent)
		for term in newTerms {
			#expect(terms.contains(term))
		}

		// 10 of the old terms must have been evicted (oldest by lastSeen)
		let oldTermsRetained = terms.filter { $0.hasPrefix("old_") }
		#expect(oldTermsRetained.count == maxEntries - 10)
	}
}
