//
//  TranscriptionClient.swift
//  Kol
//
//  Created by Kit Langton on 1/24/25.
//

import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

private let transcriptionLogger = KolLog.transcription
private let modelsLogger = KolLog.models
private let parakeetLogger = KolLog.parakeet

extension TranscriptionClient: DependencyKey {
  public static var liveValue: Self {
    let live = TranscriptionClientLive.shared
    return Self(
      transcribe: { url, model, options, skipSilence, vocab, progress in
        return try await live.transcribe(url: url, model: model, skipSilence: skipSilence, vocabularyHints: vocab, progressCallback: progress)
      },
      downloadModel: { try await live.downloadAndLoadModel(variant: $0, progressCallback: $1) },
      deleteModel: { try await live.deleteModel(variant: $0) },
      isModelDownloaded: { await live.isModelDownloaded($0) },
      isParakeet: { ParakeetModel(rawValue: $0) != nil }
    )
  }
}

actor TranscriptionClientLive {
  static let shared = TranscriptionClientLive()

  private var parakeet: ParakeetClient = ParakeetClient()
  private var currentModelName: String?

  #if canImport(FluidAudio)
  private var vad: VadManager?
  #endif

  func downloadAndLoadModel(variant: String, progressCallback: @escaping (Progress) -> Void) async throws {
    try await parakeet.ensureLoaded(modelName: variant, progress: progressCallback)
    currentModelName = variant
  }

  func deleteModel(variant: String) async throws {
    try await parakeet.deleteCaches(modelName: variant)
    if currentModelName == variant { currentModelName = nil }
  }

  func isModelDownloaded(_ modelName: String) async -> Bool {
    let available = await parakeet.isModelAvailable(modelName)
    parakeetLogger.debug("Parakeet available? \(available)")
    return available
  }

  func transcribe(
    url: URL,
    model: String,
    skipSilence: Bool,
    vocabularyHints: [String]?,
    progressCallback: @escaping (Progress) -> Void
  ) async throws -> String {
    let startAll = Date()

    // VAD silence gate
    if skipSilence, !(await containsSpeech(url)) {
      transcriptionLogger.notice("VAD detected no speech in \(url.lastPathComponent, privacy: .public) — skipping transcription")
      return ""
    }

    transcriptionLogger.notice("Transcribing with Parakeet model=\(model) file=\(url.lastPathComponent)")
    let startLoad = Date()
    try await downloadAndLoadModel(variant: model) { p in
      progressCallback(p)
    }
    transcriptionLogger.info("Parakeet ensureLoaded took \(String(format: "%.2f", Date().timeIntervalSince(startLoad)))s")

    // Configure vocabulary boosting if hints are available
    if let hints = vocabularyHints, !hints.isEmpty {
      do {
        try await parakeet.configureVocabularyBoosting(terms: hints)
      } catch {
        transcriptionLogger.error("Vocabulary boosting setup failed: \(error.localizedDescription)")
      }
    }

    let preparedClip = try ParakeetClipPreparer.ensureMinimumDuration(url: url, logger: parakeetLogger)
    defer { preparedClip.cleanup() }
    let startTx = Date()
    let text = try await parakeet.transcribe(preparedClip.url)
    transcriptionLogger.info("Parakeet transcription took \(String(format: "%.2f", Date().timeIntervalSince(startTx)))s")
    transcriptionLogger.info("Parakeet request total elapsed \(String(format: "%.2f", Date().timeIntervalSince(startAll)))s")
    return text
  }

  // MARK: - Private

  private func containsSpeech(_ url: URL) async -> Bool {
    #if canImport(FluidAudio)
    do {
      if vad == nil {
        let t0 = Date()
        vad = try await VadManager(config: VadConfig(defaultThreshold: 0.90))
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
        transcriptionLogger.notice("VAD initialized in \(elapsed, privacy: .public)s")
      }
      guard let vad else { return true }
      let t0 = Date()
      let results = try await vad.process(url)
      let totalSamples = results.count * VadManager.chunkSize
      let segConfig = VadSegmentationConfig(minSpeechDuration: 0.30)
      let segments = await vad.segmentSpeech(from: results, totalSamples: totalSamples, config: segConfig)
      let hasSpeech = !segments.isEmpty
      let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
      let elapsed = String(format: "%.3f", Date().timeIntervalSince(t0))
      transcriptionLogger.notice("VAD check took \(elapsed, privacy: .public)s — segments=\(segments.count, privacy: .public) totalSpeech=\(String(format: "%.2f", totalDuration), privacy: .public)s chunks=\(results.count, privacy: .public) speech=\(hasSpeech, privacy: .public)")
      return hasSpeech
    } catch {
      transcriptionLogger.error("VAD check failed, proceeding with transcription: \(error.localizedDescription)")
      return true
    }
    #else
    return true
    #endif
  }
}
