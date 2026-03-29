import Foundation

public extension URL {
	static var kolApplicationSupport: URL {
		get throws {
			let fm = FileManager.default
			let appSupport = try fm.url(
				for: .applicationSupportDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: true
			)
			let kolDirectory = appSupport.appendingPathComponent("com.alandotcom.Kol", isDirectory: true)
			try fm.createDirectory(at: kolDirectory, withIntermediateDirectories: true)
			return kolDirectory
		}
	}

	static var legacyDocumentsDirectory: URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
	}

	/// Legacy Hex Application Support directory for migration.
	static var legacyHexApplicationSupport: URL? {
		let fm = FileManager.default
		guard let appSupport = try? fm.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: false
		) else { return nil }
		let hexDir = appSupport.appendingPathComponent("com.kitlangton.Hex", isDirectory: true)
		return fm.fileExists(atPath: hexDir.path) ? hexDir : nil
	}

	static func kolMigratedFileURL(named fileName: String) -> URL {
		let newURL = (try? kolApplicationSupport.appending(component: fileName))
			?? documentsDirectory.appending(component: fileName)
		let legacyURL = legacyDocumentsDirectory.appending(component: fileName)
		FileManager.default.migrateIfNeeded(from: legacyURL, to: newURL)
		// Also migrate from old Hex Application Support path
		if let hexDir = legacyHexApplicationSupport {
			let hexURL = hexDir.appending(component: fileName)
			FileManager.default.migrateIfNeeded(from: hexURL, to: newURL)
		}
		return newURL
	}

	static var kolModelsDirectory: URL {
		get throws {
			let modelsDirectory = try kolApplicationSupport.appendingPathComponent("models", isDirectory: true)
			try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
			return modelsDirectory
		}
	}
}

public extension FileManager {
	func migrateIfNeeded(from legacy: URL, to new: URL) {
		guard fileExists(atPath: legacy.path), !fileExists(atPath: new.path) else { return }
		try? copyItem(at: legacy, to: new)
	}

	func removeItemIfExists(at url: URL) {
		guard fileExists(atPath: url.path) else { return }
		try? removeItem(at: url)
	}
}
