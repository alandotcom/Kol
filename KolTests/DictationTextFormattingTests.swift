import Foundation
import Testing
@testable import KolCore

struct DictationTextFormattingTests {
    @Test(arguments: ["Hello", "Hello.", "こんにちは"])
    func addsOneSpaceToText(_ text: String) {
        #expect(DictationInsertionFormatter.format(text, appendSpace: true) == text + " ")
        #expect(DictationInsertionFormatter.format(text, appendSpace: false) == text)
    }

    @Test(arguments: ["", " \t\n", "Hello ", "Hello\n", "Hello\t", "Hello\u{00a0}"])
    func preservesExistingWhitespace(_ text: String) {
        #expect(DictationInsertionFormatter.format(text, appendSpace: true) == text)
    }

    @Test(arguments: [
        ("Um, hello, uh, world.", "hello, world."),
        ("Well, um, that's ah fine.", "Well, that's fine."),
        ("UMMM uhhh AHHH!", ""),
        ("um, uh... ah?!", ""),
        ("um, first\nuh, second", "first\nsecond"),
        ("thumb album ahoy like you know uh-oh um's", "thumb album ahoy like you know uh-oh um's"),
        ("", "")
    ])
    func cleansOnlyStandaloneFillers(_ input: String, _ expected: String) {
        #expect(FillerWordCleanup.apply(input) == expected)
    }

    @Test
    func settingsDefaultOffAndPersistIndependently() throws {
        let defaults = try JSONDecoder().decode(KolSettings.self, from: Data("{}".utf8))
        #expect(!defaults.appendSpaceAfterDictation)
        #expect(!defaults.removeFillerWords)
        var settings = KolSettings()
        settings.appendSpaceAfterDictation = true
        settings.removeFillerWords = true
        settings.wordRemovalsEnabled = true
        settings.wordRemovals = [WordRemoval(pattern: "example")]
        let decoded = try JSONDecoder().decode(KolSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.wordRemovalsEnabled)
        #expect(decoded.wordRemovals == settings.wordRemovals)
    }
}
