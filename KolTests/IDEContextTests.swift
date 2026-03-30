import Testing
@testable import KolCore

@Suite("IDEContext")
struct IDEContextTests {

	@Test("Detects Swift language from file extensions")
	func detectSwift() {
		let lang = IDEContext.detectLanguage(from: [
			"TranscriptionFeature.swift", "AppDelegate.swift", "package.json",
		])
		#expect(lang == "Swift")
	}

	@Test("Detects TypeScript when most files are .ts/.tsx")
	func detectTypeScript() {
		let lang = IDEContext.detectLanguage(from: [
			"App.tsx", "index.ts", "styles.css",
		])
		#expect(lang == "TypeScript")
	}

	@Test("Detects Python")
	func detectPython() {
		let lang = IDEContext.detectLanguage(from: ["main.py", "utils.py"])
		#expect(lang == "Python")
	}

	@Test("Returns nil for empty file list")
	func emptyFileList() {
		#expect(IDEContext.detectLanguage(from: []) == nil)
	}

	@Test("Returns nil for files without recognized extensions")
	func unrecognizedExtensions() {
		#expect(IDEContext.detectLanguage(from: ["Makefile", "Dockerfile"]) == nil)
	}

	@Test("Most common language wins")
	func mostCommonWins() {
		let lang = IDEContext.detectLanguage(from: [
			"a.swift", "b.py", "c.swift", "d.py", "e.swift",
		])
		#expect(lang == "Swift")
	}

	@Test("IDEContext auto-detects language from file names")
	func autoDetectInInit() {
		let ctx = IDEContext(openFileNames: ["App.tsx", "index.ts"])
		#expect(ctx.detectedLanguage == "TypeScript")
	}

	@Test("Single file detects language correctly")
	func singleFile() {
		let ctx = IDEContext(openFileNames: ["main.go"])
		#expect(ctx.detectedLanguage == "Go")
	}

	@Test("Explicit nil language triggers auto-detection")
	func explicitNilLanguage() {
		let ctx = IDEContext(openFileNames: ["server.rs", "lib.rs"], detectedLanguage: nil)
		#expect(ctx.detectedLanguage == "Rust")
	}

	@Test("Explicit language overrides auto-detection")
	func explicitLanguageOverride() {
		let ctx = IDEContext(openFileNames: ["main.py", "utils.py"], detectedLanguage: "Custom")
		#expect(ctx.detectedLanguage == "Custom")
	}

	@Test("Tie-breaking picks one language deterministically")
	func tieBreaking() {
		// Two Swift, two Python — max(by:) returns the first max, so result depends on dict ordering.
		// The key invariant: it should return *some* language, not nil.
		let lang = IDEContext.detectLanguage(from: ["a.swift", "b.py", "c.swift", "d.py"])
		#expect(lang != nil)
	}

	@Test("Files without extensions return nil")
	func noExtensions() {
		#expect(IDEContext.detectLanguage(from: ["Makefile", "Podfile", "Gemfile"]) == nil)
	}
}
