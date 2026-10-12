import Foundation

/// Fixed input lengths for the local cleanup Core ML model.
///
/// The model accepts any query length from 1 to 1,024 tokens. The app loads it with the
/// `.infrequent` reshape hint, which makes Core ML build and keep a GPU plan for each distinct
/// input shape. Padding each call up to one of a few lengths keeps that to a handful of plans.
///
/// Padding is safe because the model writes the padded rows into cache positions after the real
/// tokens. The causal mask hides those positions from every real row, and later calls overwrite
/// them, the same way rejected draft tokens are overwritten during verification.
public enum LocalCleanupShapes {
    /// Lengths for the first call, which processes the whole prompt.
    public static let prefillLengths = [64, 96, 128, 192, 256, 320, 384, 448, 512, 640, 768, 1024]
    /// Lengths for later calls: one new token, optionally followed by up to 32 draft tokens.
    public static let stepLengths = [1, 9, 17, 33]

    /// Returns the padded query length for `count` real tokens starting at cache `position`.
    /// The result is never smaller than `count` and never extends past `capacity`.
    public static func paddedLength(count: Int, position: Int, capacity: Int) -> Int {
        let room = capacity - position
        precondition(count >= 1 && count <= room, "Query does not fit in the model cache")
        let lengths = position == 0 ? prefillLengths : stepLengths
        return min(lengths.first { $0 >= count } ?? room, room)
    }
}
