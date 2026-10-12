import Foundation

/// Chooses where to continue copying from the original transcript during local cleanup.
///
/// Most of a cleaned transcript repeats the dictated text, so after each model call the app
/// proposes the next transcript tokens as a draft and the model verifies them in one call. The
/// draft position is found by matching the newest output tokens against the transcript.
/// Dictation often repeats near-identical phrases, so several positions can match; the match
/// nearest the previous position is the one being copied. A wrong draft never changes the
/// result, because every proposed token is verified, but it costs an extra model call.
public enum LocalCleanupDraft {
    /// Longest output suffix tried as a match key.
    public static let maximumSuffix = 8
    /// How far before the previous position a match may start.
    public static let lookback = 64

    /// Returns the transcript index just after the best match for the end of `output`, or nil
    /// when no suffix of `output` appears in `draft` within the lookback window.
    public static func nextCursor(draft: [Int], output: [Int], cursor: Int) -> Int? {
        let lower = max(0, cursor - lookback)
        for length in stride(from: min(maximumSuffix, output.count), through: 1, by: -1) {
            let upper = draft.count - length
            guard lower <= upper else { continue }
            let suffix = output.suffix(length)
            var best: Int?
            for start in lower...upper where draft[start..<start + length].elementsEqual(suffix) {
                if best.map({ abs(start + length - cursor) < abs($0 + length - cursor) }) ?? true { best = start }
            }
            if let best { return best + length }
        }
        return nil
    }
}
