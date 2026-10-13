import Foundation

/// Context extracted from a messaging or email conversation.
/// Provides conversation identity for the LLM prompt layer.
public struct ConversationContext: Sendable, Equatable {
	/// Channel or DM name extracted from the window title (e.g., "#engineering", "Alice Johnson").
	public let conversationName: String?

	public init(conversationName: String? = nil) {
		self.conversationName = conversationName
	}

	/// Extract the conversation name from a window title.
	/// Most messaging apps use "AppName - ConversationName" or "AppName - ConversationName - extra info",
	/// so the first " - " component (the app name) is dropped. Messages titles its window with the
	/// conversation name alone, so for Messages a title without a separator is the name itself.
	/// Returns nil for an empty title, or a separator-free title from any other app.
	public static func conversationName(fromWindowTitle title: String?, bundleID: String? = nil) -> String? {
		guard let title, !title.isEmpty else { return nil }
		let components = title.components(separatedBy: " - ")
		if components.count < 2, bundleID?.lowercased() == "com.apple.mobilesms" {
			let name = title.trimmingCharacters(in: .whitespaces)
			return name.isEmpty || name == "Messages" ? nil : name
		}
		guard components.count >= 2 else { return nil }
		// Drop the first component (app name), rejoin the rest
		let name = components.dropFirst().joined(separator: " - ")
		return name.isEmpty ? nil : name
	}
}
