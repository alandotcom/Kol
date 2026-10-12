import Testing
@testable import KolCore

struct LocalCleanupFormattingTests {
    @Test func convertsContextualNameInLongDictation() {
        let text = "Keep the original quantity. Yuki Tanaka will review the draft. Please ask at Yuki Tanaka to check the handover."
        #expect(LocalCleanupFormatting.mentions(in: text, vocabulary: ["Yuki Tanaka"], focusedText: nil, enabled: true) == "Keep the original quantity. Yuki Tanaka will review the draft. Please ask @Yuki Tanaka to check the handover.")
    }

    @Test func preservesNamesWhenMentionsAreDisabledOrAbsent() {
        let text = "Please ask at Yuki Tanaka to review it."
        #expect(LocalCleanupFormatting.mentions(in: text, vocabulary: ["Yuki Tanaka"], focusedText: nil, enabled: false) == text)
        #expect(LocalCleanupFormatting.mentions(in: text, vocabulary: [], focusedText: "Carlos Mendes: Ready.", enabled: true) == text)
    }

    @Test func usesExactFocusedNameAndCollapsesRepeatedAt() {
        #expect(LocalCleanupFormatting.mentions(in: "Ask at at Yuki Tanaka.", vocabulary: [], focusedText: "Yuki Tanaka: Ready.", enabled: true) == "Ask @Yuki Tanaka.")
        #expect(LocalCleanupFormatting.mentions(in: "Yuki Tanaka is ready. Ask @Yuki Tanaka.", vocabulary: ["Yuki Tanaka"], focusedText: nil, enabled: true) == "Yuki Tanaka is ready. Ask @Yuki Tanaka.")
    }

    @Test func preservesQuotedDiscussionAndSubstringNames() {
        #expect(LocalCleanupFormatting.mentions(in: "The phrase \"at Yuki Tanaka\" contains three words.", vocabulary: ["Yuki Tanaka"], focusedText: nil, enabled: true) == "The phrase \"at Yuki Tanaka\" contains three words.")
        #expect(LocalCleanupFormatting.mentions(in: "Ask at Carlos Mendess.", vocabulary: ["Carlos Mendes"], focusedText: nil, enabled: true) == "Ask at Carlos Mendess.")
    }

    @Test func preservesCurlyQuotesAndNestedCodeDiscussion() {
        for text in ["The phrase “at Yuki Tanaka” is literal.", "Write 'at Yuki Tanaka' literally.", "The string \"`at Yuki Tanaka`\" is literal.", "Write 'Don't ask at Yuki Tanaka' literally.", "Write ‘Don’t ask at Yuki Tanaka’ literally."] {
            #expect(LocalCleanupFormatting.mentions(in: text, vocabulary: ["Yuki Tanaka"], focusedText: nil, enabled: true) == text)
        }
        #expect(LocalCleanupFormatting.mentions(in: "Don't forget to ask at Yuki Tanaka.", vocabulary: ["Yuki Tanaka"], focusedText: nil, enabled: true) == "Don't forget to ask @Yuki Tanaka.")
    }
}
