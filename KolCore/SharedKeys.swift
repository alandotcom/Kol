import ComposableArchitecture
import Foundation

// MARK: - KolSettings (file-backed)

public extension SharedReaderKey
	where Self == FileStorageKey<KolSettings>.Default
{
	static var kolSettings: Self {
		Self[
			.fileStorage(.kolSettingsURL),
			default: .init()
		]
	}
}

public extension URL {
	static var kolSettingsURL: URL {
		URL.kolMigratedFileURL(named: "hex_settings.json")
	}
}

// MARK: - TranscriptionHistory (file-backed)

public extension SharedReaderKey
	where Self == FileStorageKey<TranscriptionHistory>.Default
{
	static var transcriptionHistory: Self {
		Self[
			.fileStorage(.transcriptionHistoryURL),
			default: .init()
		]
	}
}

public extension URL {
	static var transcriptionHistoryURL: URL {
		URL.kolMigratedFileURL(named: "transcription_history.json")
	}
}

// MARK: - ModelBootstrapState (in-memory)

public struct ModelBootstrapState: Equatable, Sendable {
	public var isModelReady: Bool
	public var progress: Double
	public var lastError: String?
	public var modelIdentifier: String?
	public var modelDisplayName: String?

	public init(
		isModelReady: Bool = true,
		progress: Double = 1,
		lastError: String? = nil,
		modelIdentifier: String? = nil,
		modelDisplayName: String? = nil
	) {
		self.isModelReady = isModelReady
		self.progress = progress
		self.lastError = lastError
		self.modelIdentifier = modelIdentifier
		self.modelDisplayName = modelDisplayName
	}
}

public extension SharedReaderKey
	where Self == InMemoryKey<ModelBootstrapState>.Default
{
	static var modelBootstrapState: Self {
		Self[
			.inMemory("modelBootstrapState"),
			default: .init()
		]
	}
}

// MARK: - Bool flags (in-memory)

public extension SharedReaderKey
	where Self == InMemoryKey<Bool>.Default
{
	static var isSettingHotKey: Self {
		Self[.inMemory("isSettingHotKey"), default: false]
	}

	static var isSettingPasteLastTranscriptHotkey: Self {
		Self[.inMemory("isSettingPasteLastTranscriptHotkey"), default: false]
	}

	static var isRemappingScratchpadFocused: Self {
		Self[.inMemory("isRemappingScratchpadFocused"), default: false]
	}
}
