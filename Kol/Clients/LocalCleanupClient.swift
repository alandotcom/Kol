import CoreML
import Dependencies
import Foundation
import KolCore
import Tokenizers

extension LocalCleanupClient: DependencyKey {
    public static var liveValue: Self {
        Self(process: { context in
            #if DEBUG
            let start = ContinuousClock.now
            do {
                let result = try await LocalCleanupDeadline.run(timeout: CoreMLCleanup.deadline) { try await CoreMLCleanup.shared.process(context) }
                if !CommandLine.arguments.contains(where: { $0.hasPrefix("--local-cleanup-benchmark=") }) {
                    LocalCleanupRecorder.record(context, output: result.text, outcome: "ok", elapsed: start.duration(to: .now))
                }
                return result
            } catch {
                if !CommandLine.arguments.contains(where: { $0.hasPrefix("--local-cleanup-benchmark=") }) {
                    let outcome = (error as? URLError)?.code == .timedOut ? "timeout" : "error: \(error.localizedDescription)"
                    LocalCleanupRecorder.record(context, output: nil, outcome: outcome, elapsed: start.duration(to: .now))
                }
                throw error
            }
            #else
            try await LocalCleanupDeadline.run(timeout: CoreMLCleanup.deadline) { try await CoreMLCleanup.shared.process(context) }
            #endif
        }, warmUp: { try? await CoreMLCleanup.shared.warmUp() }, prime: { await CoreMLCleanup.shared.prime() },
        isModelAvailable: { CoreMLCleanup.modelFolder != nil },
        downloadModel: { progress in try await LocalCleanupModelStore.ensure(progress: progress) })
    }
}

actor CoreMLCleanup {
    static let shared = CoreMLCleanup()
    static let capacity = 1024
    /// Longest a cleanup may take before the transcript is pasted unchanged. A replay of 135 real
    /// dictations with no limit finished every cleanup within 800 ms (median 236 ms); the slowest
    /// were short dictations during load spikes, which a 450 ms limit pasted raw. Debug builds
    /// accept --cleanup-deadline-ms=N so replays can measure completion times past it.
    static let deadline: Duration = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--cleanup-deadline-ms=") }),
           let milliseconds = Int(argument.dropFirst("--cleanup-deadline-ms=".count)) {
            return .milliseconds(milliseconds)
        }
        #endif
        return .milliseconds(800)
    }()
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

    /// The model folder: one bundled into a Debug build with KOL_LOCAL_CLEANUP_MODEL, otherwise the model
    /// LocalCleanupModelStore downloaded from Hugging Face. Nil until one of them exists.
    static var modelFolder: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("LocalCleanupModel"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Cleanup.mlmodelc").path) {
            return bundled
        }
        return LocalCleanupModelStore.isReady ? LocalCleanupModelStore.folder : nil
    }

    /// Whether Settings should offer the download (read on the main thread by the view).
    nonisolated static var isModelAvailableForSettings: Bool { modelFolder != nil }

    private func loadResources() async throws -> (MLModel, any Tokenizer) {
        guard let folder = Self.modelFolder else {
            throw LLMError.invalidConfiguration("The local cleanup model has not been downloaded")
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
            // Shapes come first so they are compiled even if the sample generation fails.
            try await compileAllShapes()
            // A short real sentence runs the whole generation path once. An empty dictation is not
            // a valid sample: the model may never end its output for one.
            try await runSample()
        }
        warming = task
        defer { warming = nil }
        try await task.value
        warmed = true
    }

    /// Runs the cleanup model once if it is already warm (see LocalCleanupClient.prime). Never loads anything; a cold
    /// app warms through warmUp.
    func prime() async {
        guard warmed else { return }
        try? await runSample()
    }

    /// Cleans a short real sentence, running the whole generation path once.
    func runSample() async throws {
        _ = try await generate(chatText: LocalCleanupPrompt.chatText(PostProcessingContext(text: "thanks see you tomorrow")))
    }

    /// Runs one prediction at every padded query length. With the `.infrequent` reshape hint,
    /// Core ML builds each length's GPU plan on first use, which can take longer than the
    /// cleanup deadline. Building them all during warm-up keeps that cost off the first
    /// dictations. The throwaway session's cache contents are never read.
    private func compileAllShapes() async throws {
        let (model, _) = try await load()
        guard model.modelDescription.outputDescriptionsByName["token_ids"] != nil else { return }
        let session = PredictionSession(state: model.makeState())
        for queryLength in Set(LocalCleanupShapes.prefillLengths + LocalCleanupShapes.stepLengths).sorted() {
            try Task.checkCancellation()
            let buffers = try session.buffers(queryLength: queryLength, capacity: Self.capacity, parallel: true)
            buffers.offset[0] = 0
            let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": buffers.ids, "cache_position": buffers.offset, "causal_mask": buffers.mask])
            let options = MLPredictionOptions()
            if let tokenOutput = buffers.tokenOutput { options.outputBackings = ["token_ids": tokenOutput] }
            _ = try await model.prediction(from: input, using: session.state, options: options)
        }
    }

    func process(_ context: PostProcessingContext) async throws -> LLMProcessingResult {
        let start = ContinuousClock.now
        KolLog.llm.debug("Local cleanup context: category \(String(describing: context.resolvedCategory), privacy: .public), conversation \(context.conversationContext?.conversationName ?? "none", privacy: .private), vocabulary \((context.vocabularyHints ?? []).joined(separator: ", "), privacy: .private), focused text \(context.focusedText != nil, privacy: .public), custom rules \(!(context.customRules ?? "").isEmpty, privacy: .public)")
        guard context.inputLanguage == nil || context.inputLanguage?.lowercased().hasPrefix("en") == true else {
            throw LLMError.invalidConfiguration("Local cleanup currently supports English dictation")
        }
        if let warming { try await warming.value }
        try Task.checkCancellation()
        // Names are fixed on both sides of the model. Matching first gives the model text that
        // already carries the right names, so it does not drop or mangle them; matching again
        // catches names the model's own edits exposed (for example a web address it joined).
        let contextNames = (context.vocabularyHints ?? []) + [context.conversationContext?.conversationName].compactMap { $0 }
        let matchStart = ContinuousClock.now
        #if DEBUG
        // Replay experiments compare the pipeline with and without the matcher.
        let matcherEnabled = !ProcessInfo.processInfo.arguments.contains("--cleanup-no-matcher")
        #else
        let matcherEnabled = true
        #endif
        let matchedTranscript = matcherEnabled ? LocalCleanupNameMatcher.apply(to: context.text, terms: contextNames, isKnownWord: VocabularyExtractor.isKnownWord) : context.text
        KolLog.llm.debug("Local cleanup name matching took \(matchStart.duration(to: .now), privacy: .public)")
        let modelContext = PostProcessingContext(text: matchedTranscript, inputLanguage: context.inputLanguage,
            sourceApp: context.sourceApp, customRules: context.customRules,
            appContextOverrides: context.appContextOverrides, ideContext: context.ideContext,
            focusedText: context.focusedText, vocabularyHints: context.vocabularyHints,
            conversationContext: context.conversationContext, resolvedCategory: context.resolvedCategory,
            atMentionEnabled: context.atMentionEnabled)
        let generationStart = ContinuousClock.now
        let generated = try await generate(chatText: LocalCleanupPrompt.chatText(modelContext))
        KolLog.llm.debug("Local cleanup generation took \(generationStart.duration(to: .now), privacy: .public) (\(generated.modelCalls, privacy: .public) calls, prefill \(Int(generated.prefillSeconds * 1000), privacy: .public) ms, decode \(Int(generated.decodeSeconds * 1000), privacy: .public) ms)")
        var trimmed = generated.text.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = LocalCleanupAddressFormatter.apply(trimmed)
        let secondMatchStart = ContinuousClock.now
        defer { KolLog.llm.debug("Local cleanup output checks took \(secondMatchStart.duration(to: .now), privacy: .public)") }
        if matcherEnabled {
            trimmed = LocalCleanupNameMatcher.apply(to: trimmed, terms: contextNames, isKnownWord: VocabularyExtractor.isKnownWord)
        }
        trimmed = LocalCleanupFormatting.mentions(in: trimmed, vocabulary: context.vocabularyHints ?? [], focusedText: context.focusedText?.plainText, enabled: context.atMentionEnabled)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 1 {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed == "EMPTY" { trimmed = "" }
        // Custom rules are part of the prompt too ("I work at Example Labs"), so their capitalized
        // names get the same check: the model may use one only where the speech sounds like it.
        let guardedNames = contextNames + [context.customRules].compactMap { $0 }
        guard LocalCleanupNameGuard.accepts(transcript: context.text, cleaned: trimmed, names: guardedNames) else {
            KolLog.llm.info("Local cleanup inserted a context name that does not match the speech; using the transcript")
            throw LLMError.invalidResponse
        }
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
