import Foundation
import HexCore

#if canImport(FluidAudio)
import FluidAudio

actor QwenClient {
	private var asr: Qwen3AsrManager?
	private var currentModel: QwenModel?
	private let logger = HexLog.parakeet

	func isModelAvailable(_ modelName: String) async -> Bool {
		guard let model = QwenModel(rawValue: modelName) else { return false }
		if currentModel == model, asr != nil { return true }

		return findModelDirectory(model) != nil
	}

	func ensureLoaded(modelName: String, progress: @escaping (Progress) -> Void) async throws {
		guard let model = QwenModel(rawValue: modelName) else {
			throw NSError(
				domain: "Qwen3",
				code: -4,
				userInfo: [NSLocalizedDescriptionKey: "Unsupported Qwen3 variant: \(modelName)"]
			)
		}
		if currentModel == model, asr != nil { return }
		if currentModel != model {
			asr = nil
		}

		let t0 = Date()
		logger.notice("Starting Qwen3 load model=\(model.identifier)")
		let p = Progress(totalUnitCount: 100)
		p.completedUnitCount = 5
		progress(p)

		guard let modelDir = findModelDirectory(model) else {
			throw NSError(
				domain: "Qwen3",
				code: -5,
				userInfo: [NSLocalizedDescriptionKey: "Caspi model not found. Place converted CoreML models in ~/Library/Application Support/FluidAudio/Models/\(model.identifier)/"]
			)
		}
		logger.notice("Loading Qwen3 models from \(modelDir.path)")
		p.completedUnitCount = 20
		progress(p)

		do {
			let manager = Qwen3AsrManager()
			try await manager.loadModels(from: modelDir)
			self.asr = manager
			self.currentModel = model
		} catch {
			logger.error("Qwen3 model load FAILED: \(error.localizedDescription)")
			throw error
		}

		p.completedUnitCount = 100
		progress(p)
		logger.notice("Qwen3 ensureLoaded completed in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
	}

	func transcribe(_ url: URL, language: String?) async throws -> String {
		guard let asr else {
			throw NSError(domain: "Qwen3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR not initialized"])
		}
		let t0 = Date()
		logger.notice("Transcribing with Qwen3 file=\(url.lastPathComponent) language=\(language ?? "auto")")

		let samples = try AudioConverter().resampleAudioFile(url)
		let text = try await asr.transcribe(audioSamples: samples, language: language)

		logger.info("Qwen3 transcription finished in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
		return text
	}

	func deleteCaches(modelName: String) async throws {
		guard let model = QwenModel(rawValue: modelName) else { return }
		let fm = FileManager.default
		for dir in modelDirectories(model) {
			if fm.fileExists(atPath: dir.path) {
				try? fm.removeItem(at: dir)
			}
		}
		asr = nil
		currentModel = nil
	}

	// MARK: - Private

	private func findModelDirectory(_ model: QwenModel) -> URL? {
		for dir in modelDirectories(model) {
			if directoryContainsRequiredFiles(dir) {
				logger.notice("Found Qwen3 cache at \(dir.path)")
				return dir
			}
		}
		return nil
	}

	private func directoryContainsRequiredFiles(_ dir: URL) -> Bool {
		let fm = FileManager.default
		guard fm.fileExists(atPath: dir.path) else { return false }
		for name in ["qwen3_asr_audio_encoder_v2", "qwen3_asr_decoder_stateful"] {
			let mlmodelc = dir.appendingPathComponent(name + ".mlmodelc")
			let mlpackage = dir.appendingPathComponent(name + ".mlpackage")
			if !fm.fileExists(atPath: mlmodelc.path) && !fm.fileExists(atPath: mlpackage.path) {
				return false
			}
		}
		let embeddings = dir.appendingPathComponent("qwen3_asr_embeddings.bin")
		let vocab = dir.appendingPathComponent("vocab.json")
		return fm.fileExists(atPath: embeddings.path) && fm.fileExists(atPath: vocab.path)
	}

	private func modelDirectories(_ model: QwenModel) -> [URL] {
		let fm = FileManager.default
		var result: [URL] = []

		// FluidAudio standard model cache (resolves to sandbox container when sandboxed)
		if let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
			result.append(support.appendingPathComponent("FluidAudio/Models/\(model.identifier)", isDirectory: true))
		}

		// App-specific support directory
		if let appSupport = try? URL.hexApplicationSupport {
			result.append(appSupport.appendingPathComponent("cache/FluidAudio/Models/\(model.identifier)", isDirectory: true))
		}

		// XDG cache (Hex sets XDG_CACHE_HOME on launch for Parakeet)
		if let xdg = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
			let xdgURL = URL(fileURLWithPath: xdg, isDirectory: true)
			result.append(xdgURL.appendingPathComponent("fluidaudio/Models/\(model.identifier)", isDirectory: true))
			result.append(xdgURL.appendingPathComponent("FluidAudio/Models/\(model.identifier)", isDirectory: true))
		}

		// Home directory fallback
		let home = fm.homeDirectoryForCurrentUser
		result.append(home.appendingPathComponent("Library/Application Support/FluidAudio/Models/\(model.identifier)", isDirectory: true))
		result.append(home.appendingPathComponent(".cache/FluidAudio/Models/\(model.identifier)", isDirectory: true))

		for dir in result {
			logger.debug("Qwen3 search path: \(dir.path) exists=\(fm.fileExists(atPath: dir.path))")
		}

		return result
	}
}

#else

actor QwenClient {
	func isModelAvailable(_ modelName: String) async -> Bool { false }
	func ensureLoaded(modelName: String, progress: @escaping (Progress) -> Void) async throws {
		throw NSError(
			domain: "Qwen3",
			code: -2,
			userInfo: [NSLocalizedDescriptionKey: "Qwen3 ASR not available. FluidAudio not linked."]
		)
	}
	func transcribe(_ url: URL, language: String?) async throws -> String {
		throw NSError(domain: "Qwen3", code: -3, userInfo: [NSLocalizedDescriptionKey: "Qwen3 not available"])
	}
	func deleteCaches(modelName: String) async throws {}
}

#endif
