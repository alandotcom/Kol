import CoreML
import Dependencies
import Foundation
import KolCore
import Tokenizers

extension LocalCleanupClient: DependencyKey {
    public static var liveValue: Self {
        Self(process: { context in
            try await LocalCleanupDeadline.run { try await CoreMLCleanup.shared.process(context) }
        }, warmUp: { try? await CoreMLCleanup.shared.warmUp() })
    }
}

actor CoreMLCleanup {
    static let shared = CoreMLCleanup()
    static let capacity = 1024
    private var resources: (MLModel, any Tokenizer)?
    private var loading: Task<(MLModel, any Tokenizer), Error>?
    private var warming: Task<Void, Error>?
    private var warmed = false
    /// Prediction session kept between requests (see PredictionSession). A request that starts
    /// while another still holds it, for example after a deadline timeout, gets a fresh session.
    private var idleSession: PredictionSession?

    private func load() async throws -> (MLModel, any Tokenizer) {
        if let resources { return resources }
        if let loading { return try await loading.value }
        let task = Task { try await loadResources() }
        loading = task
        defer { loading = nil }
        let value = try await task.value
        resources = value
        return value
    }

    private func loadResources() async throws -> (MLModel, any Tokenizer) {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("LocalCleanupModel"),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("Cleanup.mlmodelc").path) else {
            throw LLMError.invalidConfiguration("The local cleanup model is not included in this build")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        // With the default reshape frequency, GPU memory grew by 40-80 MB per cleanup on an M5 Pro
        // and never came back, reaching tens of gigabytes over a long session. `.infrequent`
        // makes Core ML build one plan per input shape and keep it, which held memory flat over
        // 1,000 cleanups. LocalCleanupShapes pads every call to one of a few lengths so that
        // only a handful of plans are ever built.
        configuration.optimizationHints.reshapeFrequency = .infrequent
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cleanup-compute=gpu") {
            configuration.computeUnits = .cpuAndGPU
        } else if ProcessInfo.processInfo.arguments.contains("--cleanup-compute=cpu") {
            configuration.computeUnits = .cpuOnly
        }
        #endif
        let model = try await MLModel.load(contentsOf: folder.appendingPathComponent("Cleanup.mlmodelc"), configuration: configuration)
        let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
        return (model, tokenizer)
    }

    func warmUp() async throws {
        guard !warmed else { return }
        if let warming { return try await warming.value }
        let task = Task {
            _ = try await generate(chatText: LocalCleanupPrompt.chatText(PostProcessingContext(text: "")))
        }
        warming = task
        defer { warming = nil }
        try await task.value
        warmed = true
    }

    func process(_ context: PostProcessingContext) async throws -> LLMProcessingResult {
        let start = ContinuousClock.now
        let mentionVocabulary = context.vocabularyHints ?? []
        let context = LocalCleanupContext.includingAppVocabulary(context)
        guard context.inputLanguage == nil || context.inputLanguage?.lowercased().hasPrefix("en") == true else {
            throw LLMError.invalidConfiguration("Local cleanup currently supports English dictation")
        }
        if let warming { try await warming.value }
        try Task.checkCancellation()
        let generated = try await generate(chatText: LocalCleanupPrompt.chatText(context))
        var trimmed = generated.text.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = LocalCleanupFormatting.mentions(in: trimmed, vocabulary: mentionVocabulary, focusedText: context.focusedText?.plainText, enabled: context.atMentionEnabled)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 1 {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed == "EMPTY" { trimmed = "" }
        return LLMProcessingResult(text: trimmed.isEmpty ? context.text : trimmed, metadata: LLMMetadata(originalText: context.text, model: "kol-cleanup-360m-coreml", latencyMs: Int(Self.seconds(start) * 1000), promptTokens: generated.promptTokens, completionTokens: generated.completionTokens))
    }

    struct Generation: Codable {
        let text: String
        let promptTokens: Int
        let completionTokens: Int
        let totalSeconds: Double
        let loadSeconds: Double
        let prefillSeconds: Double
        let decodeSeconds: Double
        let preparationSeconds: Double
        let argmaxSeconds: Double
        let modelCalls: Int
        let verifiedDraftTokens: Int
    }

    private static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    /// Cache state plus input and output arrays reused across predictions and requests.
    ///
    /// Holding one set of arrays per padded length avoids allocating new inputs and outputs for
    /// every prediction. Reusing the cache state is safe because a request reads a cache position
    /// only after writing it, and the causal mask hides every later position.
    final class PredictionSession {
        struct Buffers {
            let ids: MLMultiArray
            let offset: MLMultiArray
            let mask: MLMultiArray
            let tokenOutput: MLMultiArray?
        }

        let state: MLState
        private var buffersByLength: [Int: Buffers] = [:]

        init(state: MLState) { self.state = state }

        func buffers(queryLength: Int, capacity: Int, parallel: Bool) throws -> Buffers {
            if let buffers = buffersByLength[queryLength] { return buffers }
            let buffers = Buffers(
                ids: try MLMultiArray(shape: [1, NSNumber(value: queryLength)], dataType: .int32),
                offset: try MLMultiArray(shape: [1], dataType: .int32),
                mask: try MLMultiArray(shape: [1, 1, NSNumber(value: queryLength), NSNumber(value: capacity)], dataType: .float16),
                tokenOutput: parallel ? try MLMultiArray(shape: [1, NSNumber(value: queryLength)], dataType: .int32) : nil)
            buffersByLength[queryLength] = buffers
            return buffers
        }
    }

    func generate(chatText: String) async throws -> Generation {
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Clean up dictated text")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let start = ContinuousClock.now
        try Task.checkCancellation()
        let (model, tokenizer) = try await load()
        let loadSeconds = Self.seconds(start)
        try Task.checkCancellation()
        let prompt = tokenizer.encode(text: chatText, addSpecialTokens: false)
        guard !prompt.isEmpty, prompt.count < Self.capacity else {
            throw LLMError.invalidConfiguration("Dictation context exceeds the local cleanup model capacity")
        }
        var prefillSeconds = 0.0
        var decodeSeconds = 0.0
        var preparationSeconds = 0.0
        var argmaxSeconds = 0.0
        var modelCalls = 0
        var verifiedDraftTokens = 0
        let session = idleSession ?? PredictionSession(state: model.makeState())
        idleSession = nil
        defer { idleSession = session }
        var pending = prompt
        var position = 0
        var output: [Int] = []
        let limit = min(512, Self.capacity - prompt.count)
        let parallel = model.modelDescription.outputDescriptionsByName["token_ids"] != nil
        let draft: [Int]
        if parallel,
           let user = chatText.components(separatedBy: "<|im_start|>user\n").last?.components(separatedBy: "<|im_end|>").first,
           let data = user.data(using: .utf8),
           let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let text = record["text"] as? String {
            draft = tokenizer.encode(text: text, addSpecialTokens: false)
        } else {
            draft = []
        }
        var draftCursor = 0
        while output.count < limit {
            try Task.checkCancellation()
            guard start.duration(to: .now) < .seconds(30) else { throw URLError(.timedOut) }
            let preparationStart = ContinuousClock.now
            // The token-verification model is padded to a few fixed lengths so Core ML keeps a
            // bounded set of compiled GPU programs (see LocalCleanupShapes). Padding rows repeat
            // the last real token; their outputs are ignored and their cache entries are masked.
            // The last-token logits model is not padded, since its single output is the last row.
            let queryLength = parallel ? LocalCleanupShapes.paddedLength(count: pending.count, position: position, capacity: Self.capacity) : pending.count
            let buffers = try session.buffers(queryLength: queryLength, capacity: Self.capacity, parallel: parallel)
            buffers.ids.withUnsafeMutableBytes { bytes, strides in
                let values = bytes.bindMemory(to: Int32.self)
                for index in 0..<queryLength { values[index * strides[1]] = Int32(pending[min(index, pending.count - 1)]) }
            }
            buffers.offset[0] = NSNumber(value: position)
            buffers.mask.withUnsafeMutableBytes { bytes, strides in
                let values = bytes.bindMemory(to: Float16.self)
                for query in 0..<queryLength {
                    for key in 0..<Self.capacity {
                        values[query * strides[2] + key * strides[3]] = key <= position + query ? 0 : -10000
                    }
                }
            }
            var features: [String: Any] = ["input_ids": buffers.ids, "cache_position": buffers.offset, "causal_mask": buffers.mask]
            if parallel, model.modelDescription.inputDescriptionsByName["logit_start"] != nil {
                let logitStart = try MLMultiArray(shape: [1], dataType: .int32)
                logitStart[0] = NSNumber(value: position == 0 ? pending.count - 1 : 0)
                features["logit_start"] = logitStart
            }
            let input = try MLDictionaryFeatureProvider(dictionary: features)
            let options = MLPredictionOptions()
            if let tokenOutput = buffers.tokenOutput, model.modelDescription.inputDescriptionsByName["logit_start"] == nil {
                options.outputBackings = ["token_ids": tokenOutput]
            }
            preparationSeconds += Self.seconds(preparationStart)
            let predictionStart = ContinuousClock.now
            let prediction = try await model.prediction(from: input, using: session.state, options: options)
            let predictionSeconds = Self.seconds(predictionStart)
            let argmaxStart = ContinuousClock.now
            let tokens: [Int]
            if parallel {
                guard let values = prediction.featureValue(for: "token_ids")?.multiArrayValue,
                      values.dataType == .int32,
                      values.count == queryLength || (position == 0 && values.count == 1) else { throw LLMError.invalidResponse }
                // Only the first pending.count rows are real; padded rows are discarded.
                if position == 0 {
                    tokens = [values[values.count == 1 ? 0 : pending.count - 1].intValue]
                } else {
                    tokens = (0..<pending.count).map { values[$0].intValue }
                }
            } else {
                guard let logits = prediction.featureValue(for: "logits")?.multiArrayValue,
                  logits.count == 49152, logits.dataType == .float16,
                  logits.shape == [1, 49152], logits.strides.last == 1 else { throw LLMError.invalidResponse }
                let token = logits.withUnsafeBytes { bytes in
                    let scores = bytes.bindMemory(to: Float16.self)
                    var token = 0
                    var maximum = -Float.infinity
                    for index in 0..<logits.count {
                        let value = Float(scores[index])
                        if value > maximum { maximum = value; token = index }
                    }
                    return token
                }
                tokens = [token]
            }
            argmaxSeconds += Self.seconds(argmaxStart)
            modelCalls += 1
            if position == 0 { prefillSeconds = predictionSeconds } else { decodeSeconds += predictionSeconds }
            try Task.checkCancellation()
            let prefill = position == 0
            if prefill { position = pending.count }
            for (index, token) in tokens.enumerated() {
                guard output.count < limit else { break }
                if !prefill { position += 1 }
                if token == tokenizer.eosTokenId {
                    return Generation(text: tokenizer.decode(tokens: output, skipSpecialTokens: true), promptTokens: prompt.count, completionTokens: output.count + 1, totalSeconds: Self.seconds(start), loadSeconds: loadSeconds, prefillSeconds: prefillSeconds, decodeSeconds: decodeSeconds, preparationSeconds: preparationSeconds, argmaxSeconds: argmaxSeconds, modelCalls: modelCalls, verifiedDraftTokens: verifiedDraftTokens)
                }
                output.append(token)
                if index + 1 == pending.count || token != pending[index + 1] { break }
                if !prefill { verifiedDraftTokens += 1 }
            }
            guard let last = output.last else { throw LLMError.invalidResponse }
            pending = [last]
            if parallel, !draft.isEmpty, let cursor = LocalCleanupDraft.nextCursor(draft: draft, output: output, cursor: draftCursor) {
                draftCursor = cursor
                let count = min(32, draft.count - draftCursor, limit - output.count, Self.capacity - position - 1)
                if count > 0 { pending.append(contentsOf: draft[draftCursor..<draftCursor + count]) }
            }
        }
        throw LLMError.invalidConfiguration("Local cleanup output exceeded its generation limit")
    }
}
