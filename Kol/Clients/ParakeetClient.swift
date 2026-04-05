import AVFoundation
import Foundation

#if canImport(FluidAudio)
import FluidAudio

actor ParakeetClient {
  private var asr: AsrManager?
  private var models: AsrModels?
  private var currentVariant: ParakeetModel?
  private let logger = KolLog.parakeet
  private let vendorDirs = [
    // Our app-specific cache path convention (under XDG or com.alandotcom.Kol/cache)
    "fluidaudio/Models",
    "FluidAudio/Models"
  ]

  // Vocabulary boosting (CTC rescoring)
  private var ctcModels: CtcModels?
  private var ctcSpotter: CtcKeywordSpotter?
  private var vocabularyRescorer: VocabularyRescorer?
  private var currentVocabulary: CustomVocabularyContext?

  func isModelAvailable(_ modelName: String) async -> Bool {
    guard let variant = ParakeetModel(rawValue: modelName) else {
      logger.error("Unknown Parakeet variant requested: \(modelName)")
      return false
    }
    if currentVariant == variant, asr != nil { return true }

    logger.debug("Checking Parakeet availability variant=\(variant.identifier)")
    for dir in modelDirectories(variant) {
      if directoryContainsMLModelC(dir) {
        logger.notice("Found Parakeet cache at \(dir.path)")
        return true
      }
    }
    logger.debug("No Parakeet cache detected variant=\(variant.identifier)")
    return false
  }

  private func directoryContainsMLModelC(_ dir: URL) -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dir.path) else { return false }
    if let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil) {
      for case let url as URL in en {
        if url.pathExtension == "mlmodelc" || url.lastPathComponent.hasSuffix(".mlmodelc") { return true }
      }
    }
    return false
  }

  func ensureLoaded(modelName: String, progress: @escaping (Progress) -> Void) async throws {
    guard let variant = ParakeetModel(rawValue: modelName) else {
      throw NSError(
        domain: "Parakeet",
        code: -4,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported Parakeet variant: \(modelName)"]
      )
    }
    if currentVariant == variant, asr != nil { return }
    if currentVariant != variant {
      asr = nil
      models = nil
    }
    let t0 = Date()
    logger.notice("Starting Parakeet load variant=\(variant.identifier)")
    let p = Progress(totalUnitCount: 100)
    p.completedUnitCount = 1
    progress(p)

    // Best-effort progress polling while FluidAudio downloads
    let fm = FileManager.default
    let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let faDir = support?.appendingPathComponent("FluidAudio/Models/\(variant.identifier)", isDirectory: true)
    let pollTask = Task {
      while p.completedUnitCount < 95 {
        try? await Task.sleep(for: .seconds(1))
        if let dir = faDir, let size = directorySize(dir) {
          let target: Double = 650 * 1024 * 1024 // ~650MB
          let frac = max(0.0, min(1.0, Double(size) / target))
          p.completedUnitCount = Int64(5 + frac * 90)
          progress(p)
        }
        if Task.isCancelled { break }
      }
    }
    defer { pollTask.cancel() }

    // Download + load the requested variant (returns when all assets are present)
    let models = try await AsrModels.downloadAndLoad(version: variant.asrVersion)
    self.models = models
    let manager = AsrManager(config: .init())
    try await manager.loadModels(models)
    self.asr = manager
    self.currentVariant = variant
    p.completedUnitCount = 100
    progress(p)
    logger.notice("Parakeet ensureLoaded completed in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")

    // Eagerly load CTC-110M model for vocabulary boosting (downloads ~110MB on first use)
    if ctcModels == nil {
      do {
        logger.notice("Loading CTC-110M model for vocabulary boosting...")
        ctcModels = try await CtcModels.downloadAndLoad()
        logger.notice("CTC-110M model loaded")
      } catch {
        logger.error("CTC-110M model loading failed (vocabulary boosting unavailable): \(error.localizedDescription)")
      }
    }
  }

  private func directorySize(_ dir: URL) -> UInt64? {
    let fm = FileManager.default
    guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: .skipsHiddenFiles) else { return nil }
    var total: UInt64 = 0
    for case let url as URL in en {
      if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), vals.isRegularFile == true {
        total &+= UInt64(vals.fileSize ?? 0)
      }
    }
    return total
  }

  /// Configure vocabulary boosting with extracted terms.
  /// CTC models must already be loaded via ensureLoaded().
  func configureVocabularyBoosting(terms: [String]) async throws {
    guard !terms.isEmpty, let ctcModels else {
      currentVocabulary = nil
      vocabularyRescorer = nil
      ctcSpotter = nil
      return
    }

    let vocabTerms = terms.map { CustomVocabularyTerm(text: $0) }
    let vocab = CustomVocabularyContext(terms: vocabTerms)
    currentVocabulary = vocab

    let blankId = ctcModels.vocabulary.count
    ctcSpotter = CtcKeywordSpotter(models: ctcModels, blankId: blankId)

    let ctcModelDir = CtcModels.defaultCacheDirectory(for: ctcModels.variant)
    vocabularyRescorer = try await VocabularyRescorer.create(
      spotter: ctcSpotter!,
      vocabulary: vocab,
      ctcModelDirectory: ctcModelDir
    )

    logger.notice("Vocabulary boosting configured with \(terms.count, privacy: .public) terms")
  }

  func transcribe(_ url: URL) async throws -> String {
    guard let asr else { throw NSError(domain: "Parakeet", code: -1, userInfo: [NSLocalizedDescriptionKey: "Parakeet not initialized"]) }
    let t0 = Date()
    logger.notice("Transcribing with Parakeet file=\(url.lastPathComponent)")
    let result = try await asr.transcribe(url)
    logger.info("Parakeet transcription finished in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")

    // Apply vocabulary boosting if configured
    if let rescorer = vocabularyRescorer,
       let spotter = ctcSpotter,
       let vocab = currentVocabulary,
       let timings = result.tokenTimings, !timings.isEmpty {
      let ctcStart = Date()
      do {
        let samples = try Self.loadAudioSamples(from: url)
        let spotResult = try await spotter.spotKeywordsWithLogProbs(
          audioSamples: samples,
          customVocabulary: vocab
        )
        guard !spotResult.logProbs.isEmpty else {
          logger.notice("CTC rescoring: no log probs, skipped")
          return result.text
        }

        let vocabConfig = ContextBiasingConstants.rescorerConfig(forVocabSize: vocab.terms.count)
        let rescoreOutput = rescorer.ctcTokenRescore(
          transcript: result.text,
          tokenTimings: timings,
          logProbs: spotResult.logProbs,
          frameDuration: spotResult.frameDuration,
          cbw: vocabConfig.cbw,
          minSimilarity: max(vocabConfig.minSimilarity, vocab.minSimilarity)
        )

        let ctcMs = Int(Date().timeIntervalSince(ctcStart) * 1000)
        if rescoreOutput.wasModified {
          for replacement in rescoreOutput.replacements where replacement.shouldReplace {
            logger.notice("CTC rescoring (\(ctcMs, privacy: .public)ms): '\(replacement.originalWord, privacy: .public)' → '\(replacement.replacementWord ?? "", privacy: .public)'")
          }
          return rescoreOutput.text
        } else {
          logger.notice("CTC rescoring (\(ctcMs, privacy: .public)ms): no corrections for '\(result.text, privacy: .public)' against \(vocab.terms.count, privacy: .public) terms")
        }
      } catch {
        logger.error("CTC rescoring failed, using original: \(error.localizedDescription)")
      }
    } else if vocabularyRescorer == nil {
      logger.debug("CTC rescoring: not configured (no vocabulary hints)")
    }

    return result.text
  }

  /// Load 16kHz mono Float samples from an audio file for CTC inference.
  private static func loadAudioSamples(from url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
      throw NSError(domain: "Parakeet", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
    }
    try file.read(into: buffer)
    guard let channelData = buffer.floatChannelData else {
      throw NSError(domain: "Parakeet", code: -6, userInfo: [NSLocalizedDescriptionKey: "No audio channel data"])
    }
    return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
  }

  // Delete cached Parakeet models from known locations and reset state
  func deleteCaches(modelName: String) async throws {
    guard let variant = ParakeetModel(rawValue: modelName) else { return }
    let fm = FileManager.default

    var removedAny = false
    for dir in modelDirectories(variant) {
      if fm.fileExists(atPath: dir.path) {
        try? fm.removeItem(at: dir)
        removedAny = true
      }
    }

    // Reset live objects so a future download can proceed cleanly
    if removedAny {
      self.asr = nil
      self.models = nil
      if currentVariant == variant {
        currentVariant = nil
      }
    }
  }

  /// Returns all candidate directories where a Parakeet model might be cached.
  /// Includes both exact matches and prefixed directories (e.g. versioned folders).
  private func modelDirectories(_ variant: ParakeetModel) -> [URL] {
    let fm = FileManager.default
    var result: [URL] = []

    for root in candidateRoots() {
      for vendor in vendorDirs {
        let base = root.appendingPathComponent(vendor, isDirectory: true)
        // Exact match directory
        let direct = base.appendingPathComponent(variant.identifier, isDirectory: true)
        result.append(direct)
        // Prefixed directories (e.g. versioned folders)
        if let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
          for item in items where item.lastPathComponent.hasPrefix(variant.identifier) && item != direct {
            result.append(item)
          }
        }
      }
    }
    return result
  }

  private func candidateRoots() -> [URL] {
    let fm = FileManager.default
    let xdg = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"].flatMap { URL(fileURLWithPath: $0, isDirectory: true) }
    let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    let appCache = try? URL.kolApplicationSupport.appendingPathComponent("cache", isDirectory: true)
    let userCache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache", isDirectory: true)
    return [xdg, appCache, appSupport, userCache].compactMap { $0 }
  }
}

private extension ParakeetModel {
  var asrVersion: AsrModelVersion {
    switch self {
    case .englishV2: return .v2
    case .multilingualV3: return .v3
    }
  }
}

#else

actor ParakeetClient {
  func isModelAvailable(_ modelName: String) async -> Bool { false }
  func ensureLoaded(modelName: String, progress: @escaping (Progress) -> Void) async throws {
    throw NSError(
      domain: "Parakeet",
      code: -2,
      userInfo: [NSLocalizedDescriptionKey: "Parakeet support not linked. Add Swift Package: https://github.com/FluidInference/FluidAudio.git and link FluidAudio to Kol."]
    )
  }
  func transcribe(_ url: URL) async throws -> String { throw NSError(domain: "Parakeet", code: -3, userInfo: [NSLocalizedDescriptionKey: "Parakeet not available"]) }
  func deleteCaches(modelName: String) async throws {}
}

#endif
