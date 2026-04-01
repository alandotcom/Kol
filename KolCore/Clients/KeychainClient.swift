import Dependencies
import DependenciesMacros
import Foundation
import Security

@DependencyClient
public struct KeychainClient: Sendable {
	public var save: @Sendable (_ key: String, _ value: String) async throws -> Void
	public var load: @Sendable (_ key: String) async -> String?
	public var delete: @Sendable (_ key: String) async throws -> Void
}

extension KeychainClient: DependencyKey {
	public static var liveValue: Self {
		let service = "com.alandotcom.Kol"
		let logger = KolLog.settings

		/// Base query with security attributes that prevent iCloud sync
		/// and restrict access to this device only.
		func baseQuery(key: String) -> [String: Any] {
			[
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: key,
				kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
				kSecAttrSynchronizable as String: false,
			]
		}

		/// Legacy query without the new security attributes — used for
		/// one-time migration of items saved before the attributes were added.
		func legacyQuery(key: String) -> [String: Any] {
			[
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: key,
			]
		}

		return Self(
			save: { key, value in
				guard let data = value.data(using: .utf8) else { return }
				let query = baseQuery(key: key)
				// Delete existing item first (both legacy and current)
				SecItemDelete(legacyQuery(key: key) as CFDictionary)
				// Add new item with security attributes
				var addQuery = query
				addQuery[kSecValueData as String] = data
				let status = SecItemAdd(addQuery as CFDictionary, nil)
				if status != errSecSuccess {
					throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
				}
			},
			load: { key in
				var query = baseQuery(key: key)
				query[kSecReturnData as String] = true
				query[kSecMatchLimit as String] = kSecMatchLimitOne
				var result: AnyObject?
				var status = SecItemCopyMatching(query as CFDictionary, &result)
				if status == errSecItemNotFound {
					// Migration: try loading with legacy query (no accessibility attrs)
					var legacy = legacyQuery(key: key)
					legacy[kSecReturnData as String] = true
					legacy[kSecMatchLimit as String] = kSecMatchLimitOne
					status = SecItemCopyMatching(legacy as CFDictionary, &result)
					if status == errSecSuccess, let data = result as? Data,
					   let value = String(data: data, encoding: .utf8) {
						logger.info("Migrating keychain item '\(key)' to device-only attributes")
						// Re-save with new attributes (deletes legacy + adds new)
						SecItemDelete(legacy as CFDictionary)
						var addQuery = baseQuery(key: key)
						addQuery[kSecValueData as String] = data
						SecItemAdd(addQuery as CFDictionary, nil)
						return value
					}
				}
				guard status == errSecSuccess, let data = result as? Data else { return nil }
				return String(data: data, encoding: .utf8)
			},
			delete: { key in
				// Delete both legacy and current to ensure cleanup
				let status = SecItemDelete(legacyQuery(key: key) as CFDictionary)
				if status != errSecSuccess && status != errSecItemNotFound {
					logger.warning("Keychain delete failed for '\(key)': OSStatus \(status)")
				}
			}
		)
	}
}

public extension DependencyValues {
	var keychain: KeychainClient {
		get { self[KeychainClient.self] }
		set { self[KeychainClient.self] = newValue }
	}
}
