import Foundation

public enum LocalCleanupContext {
    public static func includingAppVocabulary(_ context: PostProcessingContext) -> PostProcessingContext {
        guard context.text.range(of: #"\b(?:coal|kol)\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return context }
        var vocabulary = context.vocabularyHints ?? []
        if !vocabulary.contains(where: { $0.caseInsensitiveCompare("Kol") == .orderedSame }) {
            vocabulary.append("Kol")
        }
        return PostProcessingContext(text: context.text, inputLanguage: context.inputLanguage,
            sourceApp: context.sourceApp, customRules: context.customRules,
            appContextOverrides: context.appContextOverrides, ideContext: context.ideContext,
            focusedText: context.focusedText, vocabularyHints: vocabulary,
            conversationContext: context.conversationContext, resolvedCategory: context.resolvedCategory,
            atMentionEnabled: context.atMentionEnabled)
    }
}
