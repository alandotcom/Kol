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

    @Test(arguments: [
        ("This is Nox one dot three dot one.", "This is Nox 1.3.1."),
        ("Version 2 dot zero dot nine", "Version 2.0.9"),
        ("one dot three", "1.3"),
        ("🙂 one dot three and two dot four", "🙂 1.3 and 2.4"),
        ("a dot separates words", "a dot separates words"),
        ("one dot is enough", "one dot is enough"),
        ("someone dot three", "someone dot three"),
        ("three knocks on the door", "three knocks on the door")
    ])
    func formatsSpokenDottedNumbers(_ input: String, _ expected: String) {
        #expect(SpokenDottedNumberFormatter.apply(input) == expected)
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
