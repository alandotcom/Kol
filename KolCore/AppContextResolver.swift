import Foundation

/// Resolves the app context category by combining bundle ID, display name, URL, and window title signals.
/// Extends the existing `PromptLayers.appContextCategory(for:)` with URL-based refinement for browsers.
public enum AppContextResolver {
	/// Resolve the app context category from all available signals.
	/// Priority: URL-based detection (for browsers) > bundle ID / display name detection.
	public static func resolve(
		bundleID: String?,
		appName: String?,
		url: String? = nil,
		windowTitle: String? = nil
	) -> AppContextCategory? {
		// URL-based refinement takes priority (browser detection)
		if let url, let category = categoryFromURL(url) {
			return category
		}

		// Fall through to existing bundle ID + display name matching
		// Try bundle ID first, then app name
		if let category = PromptLayers.appContextCategory(for: bundleID) {
			return category
		}
		if let category = PromptLayers.appContextCategory(for: appName) {
			return category
		}
		if let windowTitle, let category = categoryFromWindowTitle(windowTitle) {
			return category
		}

		return nil
	}

	/// Web apps whose name appears as one " - " part of a browser window title, such as
	/// "(5) WhatsApp - Brave" or "Inbox (3) - user@example.com - Gmail". Used when the browser's
	/// URL cannot be read through Accessibility.
	private static let webAppTitleNames: [String: AppContextCategory] = [
		"whatsapp": .messaging, "slack": .messaging, "discord": .messaging, "telegram": .messaging,
		"messenger": .messaging, "google chat": .messaging, "microsoft teams": .messaging,
		"gmail": .email, "outlook": .email,
		"google docs": .document, "notion": .document,
	]

	private static func categoryFromWindowTitle(_ title: String) -> AppContextCategory? {
		for part in title.components(separatedBy: " - ") {
			// Drop an unread counter such as "(5) " at the start of a part.
			let name = part.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
				.trimmingCharacters(in: .whitespaces).lowercased()
			if let category = webAppTitleNames[name] { return category }
		}
		return nil
	}

	/// Map a URL to an app context category.
	/// Handles web apps running in browsers (Gmail, Slack web, Google Docs, etc.).
	private static func categoryFromURL(_ url: String) -> AppContextCategory? {
		let lowered = url.lowercased()

		// Email web apps
		for pattern in emailURLPatterns {
			if lowered.contains(pattern) { return .email }
		}

		// Messaging web apps
		for pattern in messagingURLPatterns {
			if lowered.contains(pattern) { return .messaging }
		}

		// Document web apps
		for pattern in documentURLPatterns {
			if lowered.contains(pattern) { return .document }
		}

		// Code web apps
		for pattern in codeURLPatterns {
			if lowered.contains(pattern) { return .code }
		}

		return nil
	}

	private static let emailURLPatterns = [
		"mail.google.com",
		"outlook.live.com",
		"outlook.office.com",
		"outlook.office365.com",
		"mail.superhuman.com",
		"mail.yahoo.com",
		"mail.proton.me",
		"app.fastmail.com",
	]

	private static let messagingURLPatterns = [
		"app.slack.com",
		"discord.com/channels",
		"web.telegram.org",
		"web.whatsapp.com",
		"teams.microsoft.com",
		"chat.google.com",
	]

	private static let documentURLPatterns = [
		"docs.google.com",
		"notion.so",
		"coda.io",
		"paper.dropbox.com",
		"quip.com",
	]

	private static let codeURLPatterns = [
		"github.com",
		"gitlab.com",
		"bitbucket.org",
		"codepen.io",
		"codesandbox.io",
		"stackblitz.com",
		"replit.com",
	]
}
