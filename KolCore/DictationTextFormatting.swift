import Foundation

public enum DictationInsertionFormatter {
    public static func format(_ text: String, appendSpace: Bool) -> String {
        guard appendSpace,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let last = text.last,
              !last.isWhitespace else { return text }
        return text + " "
    }
}

public enum FillerWordCleanup {
    public static func apply(_ text: String) -> String {
        WordRemovalApplier.apply(text, removals: [
            WordRemoval(pattern: #"(?<![\w'’\-])(?:um+|uh+|ah+)(?![\w'’\-])"#)
        ])
    }
}
