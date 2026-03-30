import Dependencies
import DependenciesMacros
import Foundation
import Security

@DependencyClient
struct KeychainClient: Sendable {
	var save: @Sendable (_ key: String, _ value: String) async throws -> Void
	var load: @Sendable (_ key: String) async -> String?
	var delete: @Sendable (_ key: String) async throws -> Void
}

extension KeychainClient: DependencyKey {
	static var liveValue: Self {
		let service = "com.alandotcom.Kol"

		return Self(
			save: { key, value in
				guard let data = value.data(using: .utf8) else { return }
				let query: [String: Any] = [
					kSecClass as String: kSecClassGenericPassword,
					kSecAttrService as String: service,
					kSecAttrAccount as String: key,
				]
				// Delete existing item first
				SecItemDelete(query as CFDictionary)
				// Add new item
				var addQuery = query
				addQuery[kSecValueData as String] = data
				let status = SecItemAdd(addQuery as CFDictionary, nil)
				if status != errSecSuccess {
					throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
				}
			},
			load: { key in
				let query: [String: Any] = [
					kSecClass as String: kSecClassGenericPassword,
					kSecAttrService as String: service,
					kSecAttrAccount as String: key,
					kSecReturnData as String: true,
					kSecMatchLimit as String: kSecMatchLimitOne,
				]
				var result: AnyObject?
				let status = SecItemCopyMatching(query as CFDictionary, &result)
				guard status == errSecSuccess, let data = result as? Data else { return nil }
				return String(data: data, encoding: .utf8)
			},
			delete: { key in
				let query: [String: Any] = [
					kSecClass as String: kSecClassGenericPassword,
					kSecAttrService as String: service,
					kSecAttrAccount as String: key,
				]
				SecItemDelete(query as CFDictionary)
			}
		)
	}
}

extension DependencyValues {
	var keychain: KeychainClient {
		get { self[KeychainClient.self] }
		set { self[KeychainClient.self] = newValue }
	}
}
