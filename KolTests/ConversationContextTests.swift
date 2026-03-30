import Testing
@testable import KolCore

@Suite("ConversationContext")
struct ConversationContextTests {
	// MARK: - Window title parsing

	@Test("Standard app - channel format")
	func standardChannelFormat() {
		let name = ConversationContext.conversationName(fromWindowTitle: "Slack - #engineering")
		#expect(name == "#engineering")
	}

	@Test("App - person name format")
	func personNameFormat() {
		let name = ConversationContext.conversationName(fromWindowTitle: "Slack - Alice Johnson")
		#expect(name == "Alice Johnson")
	}

	@Test("Multiple separators preserves inner ones")
	func multipleSeparators() {
		// "Slack - Alice Johnson - 2 new items" → "Alice Johnson - 2 new items"
		let name = ConversationContext.conversationName(fromWindowTitle: "Slack - Alice Johnson - 2 new items")
		#expect(name == "Alice Johnson - 2 new items")
	}

	@Test("Discord format")
	func discordFormat() {
		let name = ConversationContext.conversationName(fromWindowTitle: "Discord - #general")
		#expect(name == "#general")
	}

	@Test("Teams format")
	func teamsFormat() {
		let name = ConversationContext.conversationName(fromWindowTitle: "Microsoft Teams - Engineering")
		#expect(name == "Engineering")
	}

	@Test("No separator returns nil")
	func noSeparator() {
		let name = ConversationContext.conversationName(fromWindowTitle: "Slack")
		#expect(name == nil)
	}

	@Test("Empty title returns nil")
	func emptyTitle() {
		let name = ConversationContext.conversationName(fromWindowTitle: "")
		#expect(name == nil)
	}

	@Test("Nil title returns nil")
	func nilTitle() {
		let name = ConversationContext.conversationName(fromWindowTitle: nil)
		#expect(name == nil)
	}

	@Test("iMessage format with phone number")
	func iMessagePhone() {
		let name = ConversationContext.conversationName(fromWindowTitle: "Messages - +1 (555) 123-4567")
		#expect(name == "+1 (555) 123-4567")
	}
}
