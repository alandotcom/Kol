import Testing
@testable import KolCore

struct LocalCleanupContextTests {
    @Test func addsPublicAppSpellingWithoutScreenContext() {
        let input = PostProcessingContext(text: "Is coal working?", customRules: "Preserve technical terms.", resolvedCategory: .messaging)
        let context = LocalCleanupContext.includingAppVocabulary(input)
        #expect(context.text == input.text)
        #expect(context.vocabularyHints == ["Kol"])
        #expect(context.focusedText == nil)
        #expect(context.customRules == input.customRules)
        #expect(context.resolvedCategory == input.resolvedCategory)
        #expect(context.atMentionEnabled == false)
    }

    @Test func preservesCapturedSpellingAndOrdering() {
        let input = PostProcessingContext(text: "Does kol work?", vocabularyHints: ["Yuki Tanaka", "kol"], atMentionEnabled: true)
        let context = LocalCleanupContext.includingAppVocabulary(input)
        #expect(context.vocabularyHints == input.vocabularyHints)
        #expect(context.atMentionEnabled)
    }

    @Test func leavesUnrelatedTranscriptsAndSubstringsUntouched() {
        for text in ["Ask at Yuki Tanaka.", "Please open the coalfield map.", "This package is named kollector."] {
            let input = PostProcessingContext(text: text, vocabularyHints: ["Yuki Tanaka"])
            #expect(LocalCleanupContext.includingAppVocabulary(input).vocabularyHints == input.vocabularyHints)
        }
    }
}
