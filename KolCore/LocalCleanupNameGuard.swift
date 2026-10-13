import Foundation

/// Rejects cleanups that insert a context name the speaker did not say.
///
/// The local cleanup model may replace dictated words with a name from the vocabulary or the
/// conversation title. That is the point when the words were a misrecognized name ("has neck"
/// for "Hasnack", "coal" for "Kol"), but a small model can also pick the wrong entry and swap in
/// a name that sounds nothing like the speech. This guard compares the transcript with the
/// cleanup word by word. Wherever the cleanup introduces a word belonging to a context name, the
/// transcript words it replaced must sound similar, compared with a coarse consonant skeleton.
/// If any such change fails, the caller falls back to the transcript.
public enum LocalCleanupNameGuard {
    /// Highest normalized edit distance between consonant skeletons that still counts as similar.
    public static let maximumDistance = 0.4

    /// Returns false when `cleaned` introduces a word from `names` in place of transcript words
    /// that do not sound like it, or inserts such a word with nothing to replace.
    public static func accepts(transcript: String, cleaned: String, names: [String]) -> Bool {
        let nameWords = Set(names.flatMap(words).filter { $0.first?.isUppercase == true }.map { $0.lowercased() })
        guard !nameWords.isEmpty else { return true }
        let source = words(transcript), target = words(cleaned)
        for change in changes(source.map { $0.lowercased() }, target.map { $0.lowercased() }) {
            let introduced = target[change.target].filter { nameWords.contains($0.lowercased()) && !source.map { $0.lowercased() }[change.source].contains($0.lowercased()) }
            guard !introduced.isEmpty else { continue }
            let spoken = source[change.source].joined()
            let written = target[change.target].joined()
            if spoken.isEmpty || distance(skeleton(spoken), skeleton(written)) > maximumDistance { return false }
        }
        return true
    }

    struct Change {
        let source: Range<Int>
        let target: Range<Int>
    }

    /// Word-level differences between two sequences, from a longest-common-subsequence alignment.
    static func changes(_ a: [String], _ b: [String]) -> [Change] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [Change] = []
        var i = 0, j = 0, startI = 0, startJ = 0
        func flush() { if i > startI || j > startJ { result.append(Change(source: startI..<i, target: startJ..<j)) } }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                flush(); i += 1; j += 1; startI = i; startJ = j
            } else if j < b.count, i == a.count || table[i][j + 1] >= table[i + 1][j] {
                j += 1
            } else {
                i += 1
            }
        }
        flush()
        return result
    }

    /// Letters and digits of each word, without surrounding punctuation.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map { String($0.filter { $0.isLetter || $0.isNumber || $0 == "'" }) }.filter { !$0.isEmpty }
    }

    /// A coarse sound key: first letter, then consonants with common spelling variants merged.
    static func skeleton(_ text: String) -> String {
        var s = text.lowercased().filter(\.isLetter)
        for (from, to) in [("sch", "s"), ("sh", "s"), ("ch", "k"), ("ph", "f"), ("ck", "k"), ("q", "k"), ("c", "k"), ("z", "s"), ("x", "ks"), ("w", "v")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        guard let first = s.first else { return "" }
        var key = String(first)
        for character in s.dropFirst() where !"aeiouyh".contains(character) && key.last != character {
            key.append(character)
        }
        return key
    }

    /// Levenshtein distance divided by the longer length.
    static func distance(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return Double(a.isEmpty ? b.count : row[b.count]) / Double(max(a.count, b.count))
    }
}
