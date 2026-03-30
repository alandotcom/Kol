import Foundation

/// Context extracted from a messaging or email conversation.
/// Provides conversation identity and participant names for vocabulary boosting and @-mention insertion.
public struct ConversationContext: Sendable, Equatable {
	/// Channel or DM name extracted from the window title (e.g., "#engineering", "Alice Johnson").
	public let conversationName: String?

	/// Participant names extracted from the AX tree or name cache.
	public let participants: [String]

	/// Bundle ID of the source app.
	public let bundleID: String?

	public init(conversationName: String? = nil, participants: [String] = [], bundleID: String? = nil) {
		self.conversationName = conversationName
		self.participants = participants
		self.bundleID = bundleID
	}

	/// Extract the conversation name from a window title by splitting on " - " and dropping the first component.
	/// Most messaging apps use "AppName - ConversationName" or "AppName - ConversationName - extra info".
	/// Returns nil if the title has no separator or is empty.
	public static func conversationName(fromWindowTitle title: String?) -> String? {
		guard let title, !title.isEmpty else { return nil }
		let components = title.components(separatedBy: " - ")
		guard components.count >= 2 else { return nil }
		// Drop the first component (app name), rejoin the rest
		let name = components.dropFirst().joined(separator: " - ")
		return name.isEmpty ? nil : name
	}
}
