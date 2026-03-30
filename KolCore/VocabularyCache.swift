import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.vocabulary

// MARK: - Client

@DependencyClient
public struct VocabularyCacheClient: Sendable {
	/// Merge freshly-extracted vocabulary into the cache, incrementing counts for existing terms.
	public var merge: @Sendable (_ vocabulary: VocabularyExtractor.Result) -> Void = { _ in }

	/// Return the top N terms sorted by frequency (descending), then recency (descending).
	public var topTerms: @Sendable (_ limit: Int) -> [String] = { _ in [] }

	/// Clear the entire cache.
	public var clear: @Sendable () -> Void = {}
}

// MARK: - Live Implementation

extension VocabularyCacheClient: DependencyKey {
	public static let maxEntries = 200

	public static var liveValue: Self {
		let backing = VocabularyCacheBacking(maxEntries: maxEntries)

		return Self(
			merge: { vocabulary in
				backing.merge(vocabulary)
			},
			topTerms: { limit in
				backing.topTerms(limit: limit)
			},
			clear: {
				backing.clear()
			}
		)
	}
}

public extension DependencyValues {
	var vocabularyCache: VocabularyCacheClient {
		get { self[VocabularyCacheClient.self] }
		set { self[VocabularyCacheClient.self] = newValue }
	}
}

// MARK: - Backing Store

/// Thread-safe LRU cache backing the vocabulary client. Uses NSLock instead of actor
/// to keep callers synchronous (no async boundaries on the recording-start hot path).
private final class VocabularyCacheBacking: @unchecked Sendable {
	private let lock = NSLock()
	private var entries: [String: Entry] = [:]
	private let maxEntries: Int

	struct Entry {
		var count: Int
		var lastSeen: Date
		let originalForm: String  // Preserve original casing
	}

	init(maxEntries: Int) {
		self.maxEntries = maxEntries
	}

	func merge(_ vocabulary: VocabularyExtractor.Result) {
		lock.lock()
		defer { lock.unlock() }

		let now = Date()
		for term in vocabulary.allTerms {
			let key = term.lowercased()
			if var existing = entries[key] {
				existing.count += 1
				existing.lastSeen = now
				entries[key] = existing
			} else {
				entries[key] = Entry(count: 1, lastSeen: now, originalForm: term)
			}
		}

		evictIfNeeded()
		logger.debug("Cache size: \(self.entries.count) terms after merge")
	}

	func topTerms(limit: Int) -> [String] {
		lock.lock()
		defer { lock.unlock() }

		return entries.values
			.sorted { a, b in
				if a.count != b.count { return a.count > b.count }
				return a.lastSeen > b.lastSeen
			}
			.prefix(limit)
			.map(\.originalForm)
	}

	func clear() {
		lock.lock()
		defer { lock.unlock() }
		entries.removeAll()
	}

	private func evictIfNeeded() {
		guard entries.count > maxEntries else { return }
		let sorted = entries.sorted { $0.value.lastSeen < $1.value.lastSeen }
		let toRemove = entries.count - maxEntries
		for (key, _) in sorted.prefix(toRemove) {
			entries.removeValue(forKey: key)
		}
	}
}
