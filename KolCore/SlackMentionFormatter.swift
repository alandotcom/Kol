import Foundation

/// Adds an @ prefix to a visible name used to address someone at the start of a sentence.
/// Runs after accepted AI cleanup, so local and cloud providers use the same opt-in behavior.
public enum SlackMentionFormatter {
    public static func apply(to text: String, vocabulary: [String], focusedText: String?) -> String {
        var candidates = vocabulary
        if let focusedText,
           let regex = try? NSRegularExpression(pattern: #"\b[\p{Lu}][\p{L}'’-]*(?:[ \t]+[\p{Lu}][\p{L}'’-]*){0,3}\b"#) {
            candidates += regex.matches(in: focusedText, range: NSRange(focusedText.startIndex..., in: focusedText)).compactMap {
                Range($0.range, in: focusedText).map { String(focusedText[$0]) }
            }
        }
        let nonNames: Set<String> = ["can", "could", "would", "do", "did", "have", "are", "you", "your", "please", "thanks", "thank", "hey", "hi", "hello"]
        var seen = Set<String>()
        let names = candidates.flatMap { candidate -> [String] in
            let words = candidate.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty, !nonNames.contains(words[0].lowercased()), words.allSatisfy({ word in
                word.first?.isUppercase == true && word.allSatisfy { $0.isLetter || "'’-".contains($0) }
            }) else { return [] }
            // Slack often exposes full display names while people dictate only first names.
            return [words.joined(separator: " "), String(words[0])]
        }.filter { !nonNames.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted }.sorted { $0.count > $1.count }

        var result = text
        for name in names {
            let words = name.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[ \t]+"#)
            // Require a comma after the addressed name or an explicit greeting. Ambiguous
            // bare phrases such as "Will you review this?" stay unchanged.
            let request = #"(?:(?:can|could|would|will|do|did|have|are)[ \t]+you\b|please\b|thanks[ \t]+for\b|thank[ \t]+you[ \t]+for\b)"#
            let pattern = #"(?:^|[.!?][ \t\r\n]+|\n[ \t]*)(?:(hey|hi|hello)[, \t]+)?("# + words
                + #")(?=(?:,[ \t]+|[ \t]+)"# + request + #")"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 2), in: result), !LocalCleanupFormatting.isQuoted(result, before: range.lowerBound) else { continue }
                let hasGreeting = match.range(at: 1).location != NSNotFound
                guard hasGreeting || result[range.upperBound...].first == "," else { continue }
                result.replaceSubrange(range, with: "@" + name)
            }
        }
        return result
    }
}
