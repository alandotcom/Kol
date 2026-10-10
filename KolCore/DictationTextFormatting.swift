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

public enum SpokenDottedNumberFormatter {
    private static let digits = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"
    ]
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(?:[0-9]+|zero|one|two|three|four|five|six|seven|eight|nine)(?:[ \t]+dot[ \t]+(?:[0-9]+|zero|one|two|three|four|five|six|seven|eight|nine))+\b"#,
        options: .caseInsensitive
    )

    public static func apply(_ text: String) -> String {
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range).reversed() {
            guard let sourceRange = Range(match.range, in: text),
                  let resultRange = Range(match.range, in: result) else { continue }
            let components = text[sourceRange].split(whereSeparator: \.isWhitespace)
                .filter { $0.lowercased() != "dot" }
                .map { digits[$0.lowercased()] ?? String($0) }
            result.replaceSubrange(resultRange, with: components.joined(separator: "."))
        }
        return result
    }
}
