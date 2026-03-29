import ComposableArchitecture
import Dependencies
import Foundation

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
