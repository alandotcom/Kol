import XCTest
@testable import KolCore

final class LLMProviderPresetTests: XCTestCase {
	func testOpenRouterConfigurationAndSettingsRoundTrip() throws {
		XCTAssertEqual(LLMProviderPreset.openrouter.displayName, "OpenRouter")
		XCTAssertEqual(LLMProviderPreset.openrouter.defaultConfig.baseURL, "https://openrouter.ai/api/v1")
		XCTAssertEqual(LLMProviderPreset.openrouter.defaultConfig.modelName, "")
		var settings = KolSettings()
		XCTAssertEqual(settings.llmProviderPreset, LLMProviderPreset.groq.rawValue)
		settings.llmProviderPreset = LLMProviderPreset.openrouter.rawValue
		settings.llmProviderBaseURL = LLMProviderPreset.openrouter.defaultConfig.baseURL
		settings.llmModelName = "example/model"
		let decoded = try JSONDecoder().decode(KolSettings.self, from: JSONEncoder().encode(settings))
		XCTAssertEqual(decoded.llmProviderPreset, "openrouter")
		XCTAssertEqual(decoded.llmProviderBaseURL, settings.llmProviderBaseURL)
		XCTAssertEqual(decoded.llmModelName, "example/model")
	}

	func testOpenRouterNeverLoadsLegacyCredential() async {
		let keychain = KeychainClient(save: { _, _ in }, load: { key in
			XCTAssertEqual(key, "llmApiKey_openrouter")
			return nil
		}, delete: { _ in })
		let key = await keychain.loadLLMAPIKey(for: "openrouter")
		XCTAssertNil(key)
	}

	func testProviderCredentialTakesPrecedence() async {
		for preset in LLMProviderPreset.allCases {
			let provider = preset.rawValue
			let keychain = KeychainClient(save: { _, _ in }, load: { key in
				XCTAssertEqual(key, "llmApiKey_\(provider)")
				return "provider-test-key"
			}, delete: { _ in })
			let key = await keychain.loadLLMAPIKey(for: provider)
			XCTAssertEqual(key, "provider-test-key")
		}
	}

	func testExistingProvidersKeepLegacyFallback() async {
		let keychain = KeychainClient(save: { _, _ in }, load: { key in
			key == "llmApiKey" ? "legacy-test-key" : nil
		}, delete: { _ in })
		for preset in [LLMProviderPreset.groq, .custom] {
			let key = await keychain.loadLLMAPIKey(for: preset.rawValue)
			XCTAssertEqual(key, "legacy-test-key")
		}
	}

	func testEmptyProviderCredentialDoesNotReviveLegacyCredential() async {
		let keychain = KeychainClient(save: { _, _ in }, load: { key in
			key == "llmApiKey_groq" ? "" : "legacy-test-key"
		}, delete: { _ in })
		let key = await keychain.loadLLMAPIKey(for: "groq")
		XCTAssertEqual(key, "")
	}
}
