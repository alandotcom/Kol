import Foundation

/// Replaces misrecognized words with the matching name from the dictation's context.
///
/// Speech recognition respells names it does not know: "Verscell.com" for vercel.com, "nip" for
/// Knip, "has neck" for Hasnack. The context (screen vocabulary and conversation title) usually
/// holds the right spelling. This matcher compares every short run of words in the cleaned text
/// with every context term, by sound (a consonant skeleton) and by spelling (letter edit distance),
/// and swaps in the term when both are close. It works for any term, including ones no training
/// example covered.
///
/// Ordinary words get a stricter test, so a real word the speaker said ("vault", "deck") is not
/// turned into a similar name ("vaultly", "Deckard"). A term that is itself an ordinary word
/// ("Pellet") is never forced in; the cleanup model decides those from the sentence.
public enum LocalCleanupNameMatcher {
    /// Largest skeleton distance accepted for spans containing a word the dictionary does not know.
    public static let maximumSoundDistance = 0.34
    /// Largest letter distance accepted for spans containing a word the dictionary does not know.
    public static let maximumSpellingDistance = 0.5
    /// Largest letter distance accepted for spans made only of dictionary words, when their
    /// skeleton does not match the term exactly.
    public static let maximumKnownWordSpellingDistance = 0.25

    struct Word {
        let range: Range<String.Index>
        let text: String
    }

    /// Returns `text` with misrecognized spans replaced by the context term they match.
    /// Text inside quotation marks or backticks is literal and never changes.
    public static func apply(to text: String, terms: [String], isKnownWord lookUp: ((String) -> Bool)? = nil) -> String {
        // The dictionary lookup (NSSpellChecker in the app, on the main thread) is slow and every span of every term
        // asks about the same few words, so each distinct word is looked up once.
        var known: [String: Bool] = [:]
        func isKnownWord(_ word: String) -> Bool {
            if let value = known[word] { return value }
            let value = lookUp?(word) ?? false
            known[word] = value
            return value
        }
        let literal = literalRanges(in: text)
        let words = wordsIn(text).filter { word in !literal.contains { $0.overlaps(word.range) } }
        let candidates = terms.compactMap(Term.init).filter { !isKnownWord($0.letters) || $0.words.count > 1 || $0.hasInnerCapital }
        guard !words.isEmpty, !candidates.isEmpty else { return text }

        // Words that already spell a context term exactly stay as they are. Without this, a correct "TallyRate" could be
        // swapped for a similar term from the same screen, such as an OCR misreading "Tallykate".
        var exact = Set<Int>()
        for term in candidates where term.words.count <= words.count {
            for start in 0...(words.count - term.words.count) {
                let range = start..<start + term.words.count
                if words[range].map(\.text).joined(separator: " ") == term.text { exact.formUnion(range) }
            }
        }

        var matches: [(range: Range<Int>, term: Term, score: Double)] = []
        for term in candidates {
            let longest = min(words.count, term.words.count + 1)
            let shortest = max(1, term.words.count - 1)
            guard shortest <= longest else { continue }
            for length in shortest...longest {
                for start in 0...(words.count - length) {
                    guard (start..<start + length).allSatisfy({ !exact.contains($0) }) else { continue }
                    let span = Array(words[start..<start + length])
                    // Only words separated by spaces form a span; "vaultly.io" is one address.
                    guard zip(span, span.dropFirst()).allSatisfy({ text[$0.range.upperBound..<$1.range.lowerBound].allSatisfy(\.isWhitespace) }) else { continue }
                    let spoken = span.map { $0.text.lowercased() }.joined()
                    if spoken == term.letters, span.map(\.text).joined(separator: " ") == term.text { continue }
                    let spokenSkeleton = LocalCleanupNameGuard.skeleton(spoken)
                    // One- or two-letter sound keys ("t" for "the", "to" and "thehe") match far too much.
                    guard spokenSkeleton.count >= 2, term.skeleton.count >= 2 else { continue }
                    let sound = LocalCleanupNameGuard.distance(spokenSkeleton, term.skeleton)
                    let spelling = LocalCleanupNameGuard.distance(spoken, term.letters)
                    let allKnown = span.allSatisfy { isKnownWord($0.text.lowercased()) }
                    let accepted: Bool
                    if spoken == term.letters {
                        // Same letters, different spacing or casing: "tide wire" for TideWire,
                        // "kin taro" for Kintaro. A single ordinary word that only differs in
                        // casing ("pellet" for Pellet) is left alone.
                        accepted = span.count != term.words.count || term.words.count > 1 || term.hasInnerCapital || !allKnown
                    } else if allKnown {
                        // Ordinary words need strong evidence: an exact match on a sound key of at least
                        // four consonants ("has neck" for Hasnack), or, for a single word, a near-identical
                        // spelling that only lacks letters of the name ("nip" for Knip). Weaker matches ("in
                        // the" against "Inte", "and then" against "andthe") are recognition noise or coincidence.
                        accepted = (sound == 0 && spokenSkeleton.count >= 4 && spelling <= maximumSpellingDistance)
                            || (span.count == 1 && spelling <= maximumKnownWordSpellingDistance && isSubsequence(spoken, of: term.letters))
                    } else {
                        accepted = sound <= maximumSoundDistance && spelling <= maximumSpellingDistance
                    }
                    if accepted { matches.append((start..<start + length, term, sound + spelling)) }
                }
            }
        }

        // Apply the best non-overlapping matches, closest first, longer spans breaking ties.
        var taken = Set<Int>()
        var chosen: [(range: Range<Int>, term: Term)] = []
        for match in matches.sorted(by: { $0.score != $1.score ? $0.score < $1.score : $0.range.count > $1.range.count })
        where match.range.allSatisfy({ !taken.contains($0) }) {
            taken.formUnion(match.range)
            chosen.append((match.range, match.term))
        }
        var result = text
        for match in chosen.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let lower = words[match.range.lowerBound].range.lowerBound
            let upper = words[match.range.upperBound - 1].range.upperBound
            // A web address such as "Coarvane.io" keeps the domain in lowercase.
            let isDomain = result[upper...].range(of: #"^\.[a-z]{2,}\b"#, options: .regularExpression) != nil
            result.replaceSubrange(lower..<upper, with: isDomain ? match.term.text.lowercased() : match.term.text)
        }
        return result
    }

    /// True when every letter of `word` appears in `term` in order: the recognizer heard the name minus letters
    /// that are not pronounced ("nip" for Knip). A dictated word with letters the name lacks ("going" against an
    /// on-screen "GING") is a different word and stays.
    static func isSubsequence(_ word: String, of term: String) -> Bool {
        var remaining = Substring(term)
        for character in word {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }

    struct Term {
        let text: String
        let words: [String]
        let letters: String
        let skeleton: String
        let hasInnerCapital: Bool

        init?(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Paths, identifiers and other non-name vocabulary are left to the cleanup model.
            guard trimmed.range(of: #"^[\p{L}' ]+$"#, options: .regularExpression) != nil else { return nil }
            let letters = trimmed.lowercased().filter(\.isLetter)
            guard letters.count >= 3 else { return nil }
            text = trimmed
            words = trimmed.split(separator: " ").map(String.init)
            self.letters = letters
            skeleton = LocalCleanupNameGuard.skeleton(letters)
            hasInnerCapital = trimmed.dropFirst().contains(where: \.isUppercase) && !trimmed.contains(" ")
        }
    }

    /// Literal text that must keep its dictated spelling: anything between paired backticks or
    /// straight or curly double quotes, and the words right after an explicit cue that the
    /// speaker wants the wording kept ("the literal phrase at za vlaya", "spelled out ...").
    /// A plain "the word Hasnack" is still matched: people name things that way.
    static func literalRanges(in text: String) -> [Range<String.Index>] {
        let pattern = try! NSRegularExpression(pattern: #"`[^`]*`|"[^"]*"|“[^”]*”|(?i)\b(?:literal (?:phrase|word|text)|spelled(?: out)?)\b(?:\s+[\p{L}']+){1,4}"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    static func wordsIn(_ text: String) -> [Word] {
        var result: [Word] = []
        var start: String.Index?
        for index in text.indices {
            let isLetter = text[index].isLetter || text[index] == "'"
            if isLetter, start == nil { start = index }
            if !isLetter, let begin = start {
                result.append(Word(range: begin..<index, text: String(text[begin..<index])))
                start = nil
            }
        }
        if let begin = start { result.append(Word(range: begin..<text.endIndex, text: String(text[begin...]))) }
        return result
    }
}
