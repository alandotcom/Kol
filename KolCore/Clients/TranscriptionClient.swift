import Dependencies
import DependenciesMacros
import Foundation

/// Options for transcription.
public struct TranscriptionOptions: Sendable {
	public var language: String?
	public var detectLanguage: Bool
	public var useVADChunking: Bool

	public init(language: String? = nil, detectLanguage: Bool = false, useVADChunking: Bool = true) {
		self.language = language
		self.detectLanguage = detectLanguage
		self.useVADChunking = useVADChunking
	}
}

/// A client that transcribes audio files using ASR models.
/// The struct definition lives in KolCore;
/// the liveValue in the app target bridges to FluidAudio (Parakeet).
@DependencyClient
public struct TranscriptionClient: Sendable {
	/// Transcribes an audio file using the named model with given options.
	public var transcribe: @Sendable (
		_ audioURL: URL,
		_ model: String,
		_ options: TranscriptionOptions,
		_ skipSilence: Bool,
		_ vocabularyHints: [String]?,
		_ progressCallback: @escaping @Sendable (Progress) -> Void
	) async throws -> String

	/// Ensures a model is downloaded and loaded into memory.
	public var downloadModel: @Sendable (
		_ model: String,
		_ progressCallback: @escaping @Sendable (Progress) -> Void
	) async throws -> Void

	/// Deletes a model from disk.
	public var deleteModel: @Sendable (_ model: String) async throws -> Void

	/// Checks if a named model is already downloaded.
	public var isModelDownloaded: @Sendable (_ model: String) async -> Bool = { _ in false }

	/// Checks whether a model identifier is a Parakeet model.
	public var isParakeet: @Sendable (_ model: String) -> Bool = { _ in false }
}

extension TranscriptionClient: TestDependencyKey {
	public static let testValue = TranscriptionClient()
}

public extension DependencyValues {
	var transcription: TranscriptionClient {
		get { self[TranscriptionClient.self] }
		set { self[TranscriptionClient.self] = newValue }
	}
}
