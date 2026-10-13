#if DEBUG
import Foundation
import KolCore

/// Debug builds append every local cleanup to a JSON Lines file, so real dictations can be replayed through the
/// app when the cleanup changes (experiments/cleanup/autoresearch/replay_build.py turns the file into replay inputs).
///
/// Each line holds the time, the exact prompt record the cleanup model receives (dictation, screen vocabulary,
/// conversation, focused text, custom rules), the output, the outcome and the elapsed time. The file stays in
/// Application Support/com.alandotcom.Kol/local-cleanup-records.jsonl and is never uploaded; it holds real text.
enum LocalCleanupRecorder {
    static let url = URL.applicationSupportDirectory
        .appendingPathComponent("com.alandotcom.Kol", isDirectory: true)
        .appendingPathComponent("local-cleanup-records.jsonl")
    private static let queue = DispatchQueue(label: "com.alandotcom.Kol.local-cleanup-recorder", qos: .utility)

    static func record(_ context: PostProcessingContext, output: String?, outcome: String, elapsed: Duration) {
        guard let record = try? JSONSerialization.jsonObject(with: Data(LocalCleanupPrompt.userMessage(context).utf8)) else { return }
        let components = elapsed.components
        let line: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "record": record,
            "output": output as Any? ?? NSNull(),
            "outcome": outcome,
            "elapsed_ms": Int(Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15),
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
#endif
