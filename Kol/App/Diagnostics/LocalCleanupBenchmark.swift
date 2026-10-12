#if DEBUG
import AppKit
import Foundation
import KolCore

@MainActor
enum LocalCleanupBenchmark {
    private struct Message: Decodable {
        let role: String
        let content: String
    }
    private struct Input: Decodable {
        let id: String
        let messages: [Message]
    }
    private struct Prediction: Encodable {
        let id: String
        let response: String
    }
    private struct Diagnostic: Encodable {
        let id: String
        let generation: CoreMLCleanup.Generation?
        let error: String?
        var elapsedSeconds: Double? = nil
        var fellBack: Bool? = nil
    }

    private static func context(from row: Input) throws -> PostProcessingContext {
        guard let user = row.messages.first(where: { $0.role == "user" }),
              let record = try JSONSerialization.jsonObject(with: Data(user.content.utf8)) as? [String: Any],
              let text = record["text"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        let focused: FocusedText?
        if let value = record["focused"] as? [String: Any] {
            switch value["kind"] as? String {
            case "positioned":
                let before = value["before"] as? String ?? ""
                let selected = value["selected"] as? String ?? ""
                let after = value["after"] as? String ?? ""
                focused = FocusedText(value: before + selected + after, selectedRange: NSRange(location: before.utf16.count, length: selected.utf16.count))
            case "unpositioned":
                focused = FocusedText(value: value["visible"] as? String, selectedText: value["selected"] as? String)
            case "selection-only":
                focused = FocusedText(value: nil, selectedText: value["selected"] as? String)
            default: throw CocoaError(.fileReadCorruptFile)
            }
        } else { focused = nil }
        let ide = (record["ide"] as? [String: Any]).map {
            IDEContext(openFileNames: $0["file_names"] as? [String] ?? [], detectedLanguage: $0["language"] as? String)
        }
        let context = PostProcessingContext(text: text, inputLanguage: record["language"] as? String,
            customRules: record["custom_rules"] as? String, ideContext: ide, focusedText: focused,
            vocabularyHints: record["vocabulary"] as? [String],
            conversationContext: (record["conversation_name"] as? String).map { ConversationContext(conversationName: $0) },
            resolvedCategory: (record["category"] as? String).flatMap(AppContextCategory.init(rawValue:)),
            atMentionEnabled: record["mentions_enabled"] as? Bool ?? false)
        let reconstructed = try JSONSerialization.jsonObject(with: Data(LocalCleanupPrompt.userMessage(context).utf8)) as? NSDictionary
        guard reconstructed == record as NSDictionary, row.messages.first(where: { $0.role == "system" })?.content == LocalCleanupPrompt.system else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return context
    }

    static func startIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let inputArgument = arguments.first(where: { $0.hasPrefix("--local-cleanup-benchmark=") }),
              let outputArgument = arguments.first(where: { $0.hasPrefix("--benchmark-output=") }) else { return false }
        let input = String(inputArgument.dropFirst("--local-cleanup-benchmark=".count))
        let output = URL(fileURLWithPath: String(outputArgument.dropFirst("--benchmark-output=".count)), isDirectory: true)
        Task {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let predictionURL = output.appendingPathComponent("predictions.jsonl")
                guard !FileManager.default.fileExists(atPath: predictionURL.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                let lines = try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n")
                let inputs = try lines.map { try JSONDecoder().decode(Input.self, from: Data($0.utf8)) }
                guard !inputs.isEmpty, Set(inputs.map(\.id)).count == inputs.count else { throw CocoaError(.fileReadCorruptFile) }
                FileManager.default.createFile(atPath: predictionURL.path, contents: nil)
                let predictions = try FileHandle(forWritingTo: predictionURL)
                defer { try? predictions.close() }
                var diagnostics: [Diagnostic] = []
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                if arguments.contains("--benchmark-warmup") {
                    let start = ContinuousClock.now
                    try await CoreMLCleanup.shared.warmUp()
                    let duration = start.duration(to: .now).components
                    let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                    try encoder.encode(["seconds": seconds]).write(to: output.appendingPathComponent("warmup.json"))
                }
                for row in inputs {
                    let chat = row.messages.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
                    let response: String
                    let pipeline = arguments.contains("--benchmark-pipeline")
                    let start = ContinuousClock.now
                    do {
                        if pipeline {
                            let result = try await LocalCleanupClient.liveValue.process(context(from: row))
                            response = SpokenDottedNumberFormatter.apply(result.text)
                            let elapsed = start.duration(to: .now).components
                            diagnostics.append(Diagnostic(id: row.id, generation: nil, error: nil,
                                elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, fellBack: false))
                        } else {
                            let generation = try await CoreMLCleanup.shared.generate(chatText: chat)
                            response = generation.text
                            diagnostics.append(Diagnostic(id: row.id, generation: generation, error: nil))
                        }
                    } catch {
                        response = pipeline ? (try context(from: row)).text : ""
                        let elapsed = start.duration(to: .now).components
                        diagnostics.append(Diagnostic(id: row.id, generation: nil, error: error.localizedDescription,
                            elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, fellBack: pipeline))
                    }
                    try predictions.write(contentsOf: encoder.encode(Prediction(id: row.id, response: response)) + Data("\n".utf8))
                    try encoder.encode(diagnostics).write(to: output.appendingPathComponent("diagnostics.json"), options: .atomic)
                    FileHandle.standardOutput.write(Data("Completed \(diagnostics.count)/\(inputs.count)\n".utf8))
                }
                try predictions.synchronize()
                try Data("complete\n".utf8).write(to: output.appendingPathComponent("complete.txt"))
            } catch {
                FileHandle.standardError.write(Data("Core ML benchmark failed: \(error.localizedDescription)\n".utf8))
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
#endif
