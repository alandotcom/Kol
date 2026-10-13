import Foundation

public enum LocalCleanupFormatting {
    public static func mentions(in text: String, vocabulary: [String], focusedText: String?, enabled: Bool) -> String {
        guard enabled else { return text }
        var candidates = vocabulary
        if let focusedText {
            let pattern = #"\b[\p{Lu}][\p{L}'’-]*(?:[ \t]+[\p{Lu}][\p{L}'’-]*){0,3}\b"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                candidates += regex.matches(in: focusedText, range: NSRange(focusedText.startIndex..., in: focusedText)).compactMap {
                    Range($0.range, in: focusedText).map { String(focusedText[$0]) }
                }
            }
        }
        var seen = Set<String>()
        let names = candidates.filter { name in
            name.first?.isUppercase == true && name.allSatisfy { $0.isLetter || $0.isWhitespace || "'’-".contains($0) }
                && seen.insert(name.lowercased()).inserted
        }.sorted { $0.count > $1.count }
        var result = text
        for name in names {
            let words = name.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[ \t]+"#)
            let pattern = #"(?<![\p{L}\p{N}_@])(?:at[ \t]+)+"# + words + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result), !isQuoted(result, before: range.lowerBound) else { continue }
                result.replaceSubrange(range, with: "@" + name)
            }
        }
        return result
    }

    static func isQuoted(_ text: String, before index: String.Index) -> Bool {
        var closing: Character?
        var escaped = false
        var previous: Character?
        for position in text[..<index].indices {
            let character = text[position]
            if escaped { escaped = false; previous = character; continue }
            if character == "\\" { escaped = true; previous = character; continue }
            if let delimiter = closing {
                let nextIndex = text.index(after: position)
                let next = nextIndex < text.endIndex ? text[nextIndex] : nil
                let apostrophe = (delimiter == "'" || delimiter == "’") && previous?.isLetter == true && next?.isLetter == true
                if character == delimiter, !apostrophe { closing = nil }
            } else if character == "\"" || character == "`" {
                closing = character
            } else if character == "“" {
                closing = "”"
            } else if character == "‘" {
                closing = "’"
            } else if character == "'", previous?.isLetter != true {
                closing = "'"
            }
            previous = character
        }
        return closing != nil
    }
}
