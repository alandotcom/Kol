import Testing
@testable import KolCore

struct SlackMentionFormatterTests {
    @Test(arguments: [
        ("Yuki, can you review this?", "@Yuki, can you review this?"),
        ("hey yuki can you check this", "hey @Yuki can you check this"),
        ("Hi, Yuki Tanaka, please check the deploy.", "Hi, @Yuki Tanaka, please check the deploy."),
        ("The draft is ready. Yuki, could you review it?", "The draft is ready. @Yuki, could you review it?"),
        ("Update:\nYuki, thanks for checking.", "Update:\n@Yuki, thanks for checking.")
    ])
    func convertsDirectAddress(_ sample: (String, String)) {
        #expect(SlackMentionFormatter.apply(to: sample.0, vocabulary: ["Yuki Tanaka"], focusedText: nil) == sample.1)
    }

    @Test func usesFocusedNamesAndPreservesSpokenNameLength() {
        #expect(SlackMentionFormatter.apply(to: "Carlos, would you check this?", vocabulary: [], focusedText: "Carlos Mendes: Ready.") == "@Carlos, would you check this?")
        #expect(SlackMentionFormatter.apply(to: "Yuki, can you check this? Carlos Mendes, please review it.", vocabulary: ["Yuki Tanaka", "Carlos Mendes"], focusedText: nil) == "@Yuki, can you check this? @Carlos Mendes, please review it.")
    }

    @Test(arguments: [
        "I spoke to Yuki.", "Yuki will review the draft.", "Yuki is ready.",
        "Ask Yuki, can you review this?", "Yukiko, can you review this?",
        "@Yuki, can you review this?", "At Yuki, can you review this?",
        "The phrase \"Yuki, can you review this?\" is literal.",
        "Write `Yuki, please check this.` literally.",
        "Write “Yuki, can you review this?” literally.",
        "\"A draft. Yuki, can you check it?\"",
        "'A draft. Yuki, please check it.'",
        "Yuki Tanakas, can you check this?",
        "Yuki, your manager, approved the draft.",
        "Yuki, thanks to Carlos, finished the review.",
        "Yuki, you can deploy it.", "Yuki, your patch fixed it."
    ])
    func preservesReferencesAndLiterals(_ text: String) {
        #expect(SlackMentionFormatter.apply(to: text, vocabulary: ["Yuki Tanaka"], focusedText: nil) == text)
    }

    @Test(arguments: ["Can you review this?", "Hello, can you review this?", "Will you review this?", "Hope your week is going well."])
    func preservesOrdinaryWordsThatOverlapNames(_ text: String) {
        #expect(SlackMentionFormatter.apply(to: text, vocabulary: ["Will Carter", "Hope Chen"], focusedText: "Can you check the draft? Hello from the team. Hello Will.") == text)
    }

    @Test func disambiguatesOrdinaryWordNamesWithPunctuation() {
        #expect(SlackMentionFormatter.apply(to: "Will, can you review this?", vocabulary: ["Will Carter"], focusedText: nil) == "@Will, can you review this?")
        #expect(SlackMentionFormatter.apply(to: "Hope, could you review this?", vocabulary: ["Hope Chen"], focusedText: nil) == "@Hope, could you review this?")
        #expect(SlackMentionFormatter.apply(to: "Hello Will, can you review this?", vocabulary: ["Will Carter"], focusedText: "Hello Will.") == "Hello @Will, can you review this?")
    }

    @Test func requiresVisibleName() {
        #expect(SlackMentionFormatter.apply(to: "Yuki, can you check this?", vocabulary: [], focusedText: nil) == "Yuki, can you check this?")
        #expect(SlackMentionFormatter.apply(to: "Yuki, can you check this?", vocabulary: ["currentItem", "file.swift"], focusedText: nil) == "Yuki, can you check this?")
    }
}
