import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.conversation

// MARK: - Client

@DependencyClient
public struct NameCacheClient: Sendable {
	/// Merge participant names into the cache for a specific conversation.
	public var merge: @Sendable (_ names: [String], _ bundleID: String, _ conversationID: String) -> Void = { _, _, _ in }

	/// Retrieve cached names for a conversation, sorted by recency.
	public var names: @Sendable (_ bundleID: String, _ conversationID: String, _ limit: Int) -> [String] = { _, _, _ in [] }

	/// Retrieve all cached names across all conversations for a given app.
	public var allNames: @Sendable (_ bundleID: String, _ limit: Int) -> [String] = { _, _ in [] }

	/// Clear the entire cache.
	public var clear: @Sendable () -> Void = {}
}

// MARK: - Live Implementation

extension NameCacheClient: DependencyKey {
	public static let maxNamesPerConversation = 50
	public static let maxConversationsPerApp = 20

	public static var liveValue: Self {
		let backing = NameCacheBacking(
			maxNamesPerConversation: maxNamesPerConversation,
			maxConversationsPerApp: maxConversationsPerApp
		)

		return Self(
			merge: { names, bundleID, conversationID in
				backing.merge(names: names, bundleID: bundleID, conversationID: conversationID)
			},
			names: { bundleID, conversationID, limit in
				backing.names(bundleID: bundleID, conversationID: conversationID, limit: limit)
			},
			allNames: { bundleID, limit in
				backing.allNames(bundleID: bundleID, limit: limit)
			},
			clear: {
				backing.clear()
			}
		)
	}
}

public extension DependencyValues {
	var nameCache: NameCacheClient {
		get { self[NameCacheClient.self] }
		set { self[NameCacheClient.self] = newValue }
	}
}

// MARK: - Backing Store

/// Thread-safe LRU cache for participant names, keyed by (bundleID, conversationID).
/// Uses NSLock to keep the recording-start hot path synchronous.
private final class NameCacheBacking: @unchecked Sendable {
	private let lock = NSLock()
	private var conversations: [ConversationKey: ConversationSlot] = [:]
	private let maxNamesPerConversation: Int
	private let maxConversationsPerApp: Int

	private struct ConversationKey: Hashable {
		let bundleID: String
		let conversationID: String
	}

	private struct ConversationSlot {
		var names: [String: Date] // name -> lastSeen
		var lastAccessed: Date
	}

	init(maxNamesPerConversation: Int, maxConversationsPerApp: Int) {
		self.maxNamesPerConversation = maxNamesPerConversation
		self.maxConversationsPerApp = maxConversationsPerApp
	}

	func merge(names: [String], bundleID: String, conversationID: String) {
		lock.lock()
		defer { lock.unlock() }

		let key = ConversationKey(bundleID: bundleID, conversationID: conversationID)
		let now = Date()

		var slot = conversations[key] ?? ConversationSlot(names: [:], lastAccessed: now)
		slot.lastAccessed = now

		for name in names {
			slot.names[name] = now
		}

		// Evict oldest names if over limit
		if slot.names.count > maxNamesPerConversation {
			let sorted = slot.names.sorted { $0.value < $1.value }
			let toRemove = slot.names.count - maxNamesPerConversation
			for (name, _) in sorted.prefix(toRemove) {
				slot.names.removeValue(forKey: name)
			}
		}

		conversations[key] = slot

		// Evict oldest conversations for this app if over limit
		evictConversationsIfNeeded(bundleID: bundleID)

		logger.debug("Name cache: \(slot.names.count) names for \(conversationID, privacy: .private)")
	}

	func names(bundleID: String, conversationID: String, limit: Int) -> [String] {
		lock.lock()
		defer { lock.unlock() }

		let key = ConversationKey(bundleID: bundleID, conversationID: conversationID)
		guard let slot = conversations[key] else { return [] }

		return slot.names
			.sorted { $0.value > $1.value }
			.prefix(limit)
			.map(\.key)
	}

	func allNames(bundleID: String, limit: Int) -> [String] {
		lock.lock()
		defer { lock.unlock() }

		var allNames: [String: Date] = [:]
		for (key, slot) in conversations where key.bundleID == bundleID {
			for (name, date) in slot.names {
				if let existing = allNames[name] {
					allNames[name] = max(existing, date)
				} else {
					allNames[name] = date
				}
			}
		}

		return allNames
			.sorted { $0.value > $1.value }
			.prefix(limit)
			.map(\.key)
	}

	func clear() {
		lock.lock()
		defer { lock.unlock() }
		conversations.removeAll()
	}

	private func evictConversationsIfNeeded(bundleID: String) {
		let appConversations = conversations.filter { $0.key.bundleID == bundleID }
		guard appConversations.count > maxConversationsPerApp else { return }

		let sorted = appConversations.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
		let toRemove = appConversations.count - maxConversationsPerApp
		for (key, _) in sorted.prefix(toRemove) {
			conversations.removeValue(forKey: key)
		}
	}
}
