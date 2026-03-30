import Testing
@testable import KolCore

@Suite("AppContextResolver")
struct AppContextResolverTests {
	// MARK: - URL-based reclassification

	@Test("Gmail URL resolves to email")
	func gmailURL() {
		let category = AppContextResolver.resolve(
			bundleID: "com.google.Chrome", appName: "Google Chrome",
			url: "https://mail.google.com/mail/u/0/#inbox"
		)
		#expect(category == .email)
	}

	@Test("Outlook web URL resolves to email")
	func outlookWebURL() {
		let category = AppContextResolver.resolve(
			bundleID: "com.google.Chrome", appName: "Google Chrome",
			url: "https://outlook.live.com/mail/0/inbox"
		)
		#expect(category == .email)
	}

	@Test("Slack web URL resolves to messaging")
	func slackWebURL() {
		let category = AppContextResolver.resolve(
			bundleID: "com.apple.Safari", appName: "Safari",
			url: "https://app.slack.com/client/T12345/C67890"
		)
		#expect(category == .messaging)
	}

	@Test("Google Docs URL resolves to document")
	func googleDocsURL() {
		let category = AppContextResolver.resolve(
			bundleID: "com.google.Chrome", appName: "Google Chrome",
			url: "https://docs.google.com/document/d/abc123/edit"
		)
		#expect(category == .document)
	}

	@Test("GitHub URL resolves to code")
	func githubURL() {
		let category = AppContextResolver.resolve(
			bundleID: "com.google.Chrome", appName: "Google Chrome",
			url: "https://github.com/alandotcom/Kol/pull/42"
		)
		#expect(category == .code)
	}

	@Test("URL takes priority over bundle ID")
	func urlOverridesBundleID() {
		// Chrome's bundle ID is unknown to the app category list, but Gmail URL should win
		let category = AppContextResolver.resolve(
			bundleID: "com.google.Chrome", appName: "Google Chrome",
			url: "https://mail.google.com/mail/u/0/#inbox"
		)
		#expect(category == .email)
	}

	// MARK: - Bundle ID fallthrough

	@Test("Native Slack resolves to messaging via bundle ID")
	func nativeSlack() {
		let category = AppContextResolver.resolve(
			bundleID: "com.tinyspeck.slackmacgap", appName: "Slack"
		)
		#expect(category == .messaging)
	}

	@Test("Native Mail resolves to email via bundle ID")
	func nativeMail() {
		let category = AppContextResolver.resolve(
			bundleID: "com.apple.mail", appName: "Mail"
		)
		#expect(category == .email)
	}

	@Test("VS Code resolves to code via bundle ID")
	func vsCode() {
		let category = AppContextResolver.resolve(
			bundleID: "com.microsoft.vscode", appName: "Visual Studio Code"
		)
		#expect(category == .code)
	}

	@Test("Xcode resolves to code via bundle ID")
	func xcode() {
		let category = AppContextResolver.resolve(
			bundleID: "com.apple.dt.xcode", appName: "Xcode"
		)
		#expect(category == .code)
	}

	@Test("Notes resolves to document")
	func notes() {
		let category = AppContextResolver.resolve(
			bundleID: "com.apple.notes", appName: "Notes"
		)
		#expect(category == .document)
	}

	@Test("Unknown app returns nil")
	func unknownApp() {
		let category = AppContextResolver.resolve(
			bundleID: "com.random.app", appName: "Random App"
		)
		#expect(category == nil)
	}

	@Test("Nil bundle ID and name returns nil")
	func nilInputs() {
		let category = AppContextResolver.resolve(bundleID: nil, appName: nil)
		#expect(category == nil)
	}

	@Test("Unknown URL falls through to bundle ID")
	func unknownURLFallsThrough() {
		let category = AppContextResolver.resolve(
			bundleID: "com.tinyspeck.slackmacgap", appName: "Slack",
			url: "https://www.randomsite.com"
		)
		#expect(category == .messaging)
	}

	// MARK: - Dual detection (native + browser same category)

	@Test("Gmail native and Gmail web both resolve to email")
	func gmailDualDetection() {
		let native = AppContextResolver.resolve(
			bundleID: "com.google.Gmail", appName: "Gmail"
		)
		let web = AppContextResolver.resolve(
			bundleID: "com.google.Chrome", appName: "Google Chrome",
			url: "https://mail.google.com/mail/u/0/"
		)
		#expect(native == .email)
		#expect(web == .email)
		#expect(native == web)
	}
}
