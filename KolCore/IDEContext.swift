import Foundation

/// Context extracted from an IDE: open file names and detected language.
public struct IDEContext: Sendable, Equatable {
	public let openFileNames: [String]
	public let detectedLanguage: String?

	public init(openFileNames: [String], detectedLanguage: String? = nil) {
		self.openFileNames = openFileNames
		self.detectedLanguage = detectedLanguage ?? Self.detectLanguage(from: openFileNames)
	}

	/// Infer the primary programming language from file extensions.
	/// Returns the most common language among the open files, or nil if none detected.
	public static func detectLanguage(from fileNames: [String]) -> String? {
		var counts: [String: Int] = [:]
		for name in fileNames {
			let ext = (name as NSString).pathExtension.lowercased()
			guard let lang = extensionToLanguage[ext] else { continue }
			counts[lang, default: 0] += 1
		}
		return counts.max(by: { $0.value < $1.value })?.key
	}

	private static let extensionToLanguage: [String: String] = [
		"swift": "Swift",
		"ts": "TypeScript", "tsx": "TypeScript",
		"js": "JavaScript", "jsx": "JavaScript",
		"py": "Python",
		"rb": "Ruby",
		"go": "Go",
		"rs": "Rust",
		"java": "Java",
		"kt": "Kotlin",
		"c": "C", "h": "C",
		"cpp": "C++", "hpp": "C++", "cc": "C++",
		"m": "Objective-C", "mm": "Objective-C",
		"cs": "C#",
		"html": "HTML", "css": "CSS", "scss": "SCSS",
		"sql": "SQL",
		"sh": "Shell", "zsh": "Shell", "fish": "Shell", "bash": "Shell",
		"json": "JSON", "yaml": "YAML", "yml": "YAML", "toml": "TOML",
		"md": "Markdown",
		"vue": "Vue", "svelte": "Svelte",
	]
}
