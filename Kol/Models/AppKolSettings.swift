import ComposableArchitecture
import Dependencies
import Foundation
import KolCore

// Re-export types so the app target can use them without KolCore prefixes.
typealias RecordingAudioBehavior = KolCore.RecordingAudioBehavior
typealias KolSettings = KolCore.KolSettings

extension SharedReaderKey
	where Self == FileStorageKey<KolSettings>.Default
{
	static var kolSettings: Self {
		Self[
			.fileStorage(.kolSettingsURL),
			default: .init()
		]
	}
}

// MARK: - Storage Migration

extension URL {
	static var kolSettingsURL: URL {
		get {
			URL.kolMigratedFileURL(named: "hex_settings.json")
		}
	}
}
