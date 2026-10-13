import Testing
@testable import KolCore

struct LocalCleanupNameMatcherTests {
    private let dictionary: Set<String> = ["the", "is", "clean", "open", "settings", "vault", "was", "empty", "has", "neck",
                                           "alumni", "tide", "wire", "kin", "taro", "pellet", "stove", "on", "deck", "wet", "nip"]
    private func known(_ word: String) -> Bool { dictionary.contains(word) }

    @Test func replacesMisheardNamesFromContext() {
        #expect(LocalCleanupNameMatcher.apply(to: "Coarvane.io", terms: ["corvane", "MacBook"], isKnownWord: known) == "corvane.io")
        #expect(LocalCleanupNameMatcher.apply(to: "Nip is clean.", terms: ["Knip"], isKnownWord: known) == "Knip is clean.")
        #expect(LocalCleanupNameMatcher.apply(to: "Has neck alumni.", terms: ["Hasnack Alumni"], isKnownWord: known) == "Hasnack Alumni.")
        #expect(LocalCleanupNameMatcher.apply(to: "OK, tide wire, sounds good.", terms: ["TideWire"], isKnownWord: known) == "OK, TideWire, sounds good.")
        #expect(LocalCleanupNameMatcher.apply(to: "Open kin taro settings.", terms: ["Kintaro"], isKnownWord: known) == "Open Kintaro settings.")
        #expect(LocalCleanupNameMatcher.apply(to: "Forward this to Kasimir Oduiea.", terms: ["Kasimir Oduya"], isKnownWord: known) == "Forward this to Kasimir Oduya.")
    }

    @Test func leavesOrdinaryWordsAlone() {
        #expect(LocalCleanupNameMatcher.apply(to: "The vault was empty.", terms: ["vaultly"], isKnownWord: known) == "The vault was empty.")
        #expect(LocalCleanupNameMatcher.apply(to: "The pellet stove is on.", terms: ["Pellet"], isKnownWord: known) == "The pellet stove is on.")
        #expect(LocalCleanupNameMatcher.apply(to: "The deck is wet.", terms: ["Deckard Vale"], isKnownWord: known) == "The deck is wet.")
        // A screen acronym one letter away from an ordinary word does not replace it.
        #expect(LocalCleanupNameMatcher.apply(to: "We are going to settle it.", terms: ["GING"], isKnownWord: { ["we", "are", "going", "to", "settle", "it"].contains($0) }) == "We are going to settle it.")
    }

    @Test func keepsWordsThatAlreadySpellATerm() {
        // The screen holds the real name and an OCR misreading of it; a correct name must not become the misreading.
        let terms = ["TallyRate", "Tallykate"]
        #expect(LocalCleanupNameMatcher.apply(to: "TallyRate.", terms: terms, isKnownWord: known) == "TallyRate.")
        #expect(LocalCleanupNameMatcher.apply(to: "Tally rate.", terms: terms, isKnownWord: { ["tally", "rate"].contains($0) }) == "TallyRate.")
    }

    @Test func ignoresNonNameVocabulary() {
        #expect(LocalCleanupNameMatcher.apply(to: "Check the src folder.", terms: ["src/domains", "tidewire-data"], isKnownWord: known) == "Check the src folder.")
        #expect(LocalCleanupNameMatcher.apply(to: "Nothing to change.", terms: [], isKnownWord: known) == "Nothing to change.")
    }

    @Test func keepsLiteralTextUnchanged() {
        #expect(LocalCleanupNameMatcher.apply(to: "Run `printf \"quo rlaya-17\"` now.", terms: ["Quorlaya"], isKnownWord: known) == "Run `printf \"quo rlaya-17\"` now.")
        #expect(LocalCleanupNameMatcher.apply(to: "The literal phrase at za vlaya must remain spelled out.", terms: ["Zavlaya"], isKnownWord: known) == "The literal phrase at za vlaya must remain spelled out.")
    }

    @Test func neverReplacesShortWordsWithRecognitionNoise() {
        let words: Set<String> = ["i", "don't", "know", "what", "the", "question", "is", "can", "you", "explain", "to", "me", "he"]
        let text = "I don't know what the question is, can you explain to me?"
        #expect(LocalCleanupNameMatcher.apply(to: text, terms: ["thehe", "readsas", "contare"], isKnownWord: { words.contains($0) }) == text)
    }
}
