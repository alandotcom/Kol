import Testing
@testable import KolCore

@Suite("NameCache")
struct NameCacheTests {
	@Test("Merge and retrieve names")
	func mergeAndRetrieve() {
		let client = NameCacheClient.liveValue
		client.merge(["Alice", "Bob", "Charlie"], "com.tinyspeck.slackmacgap", "#engineering")
		let names = client.names("com.tinyspeck.slackmacgap", "#engineering", 10)
		#expect(names.count == 3)
		#expect(names.contains("Alice"))
		#expect(names.contains("Bob"))
		#expect(names.contains("Charlie"))
	}

	@Test("Names are separated by conversation")
	func separateConversations() {
		let client = NameCacheClient.liveValue
		client.merge(["Alice"], "com.tinyspeck.slackmacgap", "#engineering")
		client.merge(["Bob"], "com.tinyspeck.slackmacgap", "#design")

		let eng = client.names("com.tinyspeck.slackmacgap", "#engineering", 10)
		let design = client.names("com.tinyspeck.slackmacgap", "#design", 10)

		#expect(eng == ["Alice"])
		#expect(design == ["Bob"])
	}

	@Test("All names across conversations for an app")
	func allNamesForApp() {
		let client = NameCacheClient.liveValue
		client.merge(["Alice"], "com.tinyspeck.slackmacgap", "#engineering")
		client.merge(["Bob"], "com.tinyspeck.slackmacgap", "#design")
		client.merge(["Charlie"], "com.hnc.discord", "#general")

		let slackNames = client.allNames("com.tinyspeck.slackmacgap", 10)
		#expect(slackNames.count == 2)
		#expect(slackNames.contains("Alice"))
		#expect(slackNames.contains("Bob"))
	}

	@Test("LRU eviction at capacity")
	func eviction() {
		let client = NameCacheClient.liveValue
		// Merge more than maxNamesPerConversation (50) names
		let names = (1...60).map { "Person\($0)" }
		client.merge(names, "test.app", "convo1")

		let retrieved = client.names("test.app", "convo1", 60)
		#expect(retrieved.count == 50)
	}

	@Test("Clear removes all entries")
	func clearAll() {
		let client = NameCacheClient.liveValue
		client.merge(["Alice", "Bob"], "test.app", "convo1")
		client.clear()

		let names = client.names("test.app", "convo1", 10)
		#expect(names.isEmpty)
	}

	@Test("Duplicate names update recency")
	func duplicateUpdatesRecency() {
		let client = NameCacheClient.liveValue
		client.merge(["Alice", "Bob"], "test.app", "convo1")
		// Re-merge Alice — should update its recency
		client.merge(["Alice"], "test.app", "convo1")

		let names = client.names("test.app", "convo1", 10)
		#expect(names.count == 2)
		// Alice should be first (most recent)
		#expect(names.first == "Alice")
	}

	@Test("Empty conversation returns empty")
	func emptyConversation() {
		let client = NameCacheClient.liveValue
		let names = client.names("test.app", "nonexistent", 10)
		#expect(names.isEmpty)
	}
}
