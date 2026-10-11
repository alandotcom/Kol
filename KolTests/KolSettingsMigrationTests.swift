import XCTest
@testable import KolCore

final class KolSettingsMigrationTests: XCTestCase {
	func testV1FixtureMigratesToCurrentDefaults() throws {
		let data = try loadFixture(named: "v1")
		let decoded = try JSONDecoder().decode(KolSettings.self, from: data)

		XCTAssertEqual(decoded.recordingAudioBehavior, .pauseMedia, "Legacy pauseMediaOnRecord bool should map to pauseMedia behavior")
		XCTAssertEqual(decoded.openOnLogin, true)
		XCTAssertEqual(decoded.showDockIcon, false)
		XCTAssertEqual(decoded.selectedModel, "whisper-large-v3")
		XCTAssertEqual(decoded.useClipboardPaste, false)
		XCTAssertEqual(decoded.preventSystemSleep, true)
		XCTAssertEqual(decoded.minimumKeyTime, 0.25)
		XCTAssertEqual(decoded.copyToClipboard, true)
		XCTAssertFalse(decoded.superFastModeEnabled)
		XCTAssertEqual(decoded.useDoubleTapOnly, true)
		XCTAssertEqual(decoded.doubleTapLockEnabled, true)
		XCTAssertEqual(decoded.outputLanguage, "en")
		XCTAssertEqual(decoded.selectedMicrophoneID, "builtin:mic")
		XCTAssertEqual(decoded.saveTranscriptionHistory, false)
		XCTAssertEqual(decoded.maxHistoryEntries, 10)
		XCTAssertEqual(decoded.hasCompletedModelBootstrap, true)
		XCTAssertEqual(decoded.hasCompletedStorageMigration, true)
	}

	func testOpenRouterCatalogModelIDsSurviveLegacyModelMigration() throws {
		for model in ["meta-llama/llama-4-scout", "example/llama3.1-8b"] {
			var settings = KolSettings()
			settings.llmProviderPreset = LLMProviderPreset.openrouter.rawValue
			settings.llmProviderBaseURL = LLMProviderPreset.openrouter.defaultConfig.baseURL
			settings.llmModelName = model
			let decoded = try JSONDecoder().decode(KolSettings.self, from: JSONEncoder().encode(settings))
			XCTAssertEqual(decoded.llmModelName, model)
			XCTAssertEqual(decoded.llmProviderPreset, "openrouter")
		}
	}

	func testOpenRouterMissingModelRequiresSelection() throws {
		let payload = Data(#"{"llmProviderPreset":"openrouter"}"#.utf8)
		let decoded = try JSONDecoder().decode(KolSettings.self, from: payload)
		XCTAssertEqual(decoded.llmModelName, "")
	}

	func testExistingProvidersKeepLegacyModelMigration() throws {
		for preset in ["groq", "custom", "cerebras"] {
			for model in ["llama-4-scout-17b-16e-instruct", "llama3.1-8b"] {
				let data = try JSONSerialization.data(withJSONObject: [
					"llmProviderPreset": preset,
					"llmModelName": model,
				])
				let decoded = try JSONDecoder().decode(KolSettings.self, from: data)
				XCTAssertEqual(decoded.llmModelName, LLMProviderPreset.groq.defaultConfig.modelName)
				XCTAssertEqual(decoded.llmProviderPreset, preset == "cerebras" ? "groq" : preset)
			}
		}
	}

	func testGroqPresetLoadsCurrentDefaultModel() throws {
		let payloads: [[String: Any]] = [
			["llmProviderPreset": "groq", "llmModelName": "llama-3.3-70b-versatile"],
			["llmProviderPreset": "groq", "llmModelName": "llama-3.1-8b-instant"],
			["llmModelName": "llama-3.3-70b-versatile"],
		]
		for payload in payloads {
			let data = try JSONSerialization.data(withJSONObject: payload)
			let decoded = try JSONDecoder().decode(KolSettings.self, from: data)
			XCTAssertEqual(decoded.llmProviderPreset, LLMProviderPreset.groq.rawValue)
			XCTAssertEqual(decoded.llmModelName, LLMProviderPreset.groq.defaultConfig.modelName)
		}
	}

	func testCustomPresetKeepsUserModel() throws {
		let data = try JSONSerialization.data(withJSONObject: [
			"llmProviderPreset": "custom",
			"llmProviderBaseURL": "https://provider.example/v1",
			"llmModelName": "llama-3.3-70b-versatile",
		])
		let decoded = try JSONDecoder().decode(KolSettings.self, from: data)
		XCTAssertEqual(decoded.llmModelName, "llama-3.3-70b-versatile")
	}

	func testEncodeDecodeRoundTripPreservesDefaults() throws {
		let settings = KolSettings()
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(KolSettings.self, from: data)
		XCTAssertEqual(decoded, settings)
	}

	func testLegacySoundSettingsAreIgnoredWithoutResettingOtherPreferences() throws {
		let payload = Data(#"{"soundEffectsEnabled":true,"soundEffectsVolume":0.8,"soundTheme":"soft","showDockIcon":false,"selectedModel":"parakeet-tdt-0.6b-v2-coreml","llmCustomRules":"Use concise punctuation."}"#.utf8)
		let decoded = try JSONDecoder().decode(KolSettings.self, from: payload)

		XCTAssertFalse(decoded.showDockIcon)
		XCTAssertEqual(decoded.selectedModel, "parakeet-tdt-0.6b-v2-coreml")
		XCTAssertEqual(decoded.llmCustomRules, "Use concise punctuation.")
		let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
		XCTAssertNil(encoded["soundEffectsEnabled"])
		XCTAssertNil(encoded["soundEffectsVolume"])
		XCTAssertNil(encoded["soundTheme"])
	}

	func testInitNormalizesDoubleTapOnlyWhenLockDisabled() {
		let settings = KolSettings(useDoubleTapOnly: true, doubleTapLockEnabled: false)

		XCTAssertFalse(settings.useDoubleTapOnly)
		XCTAssertFalse(settings.doubleTapLockEnabled)
	}

	func testDecodeNormalizesDoubleTapOnlyWhenLockDisabled() throws {
		let payload = "{\"useDoubleTapOnly\":true,\"doubleTapLockEnabled\":false}"
		guard let data = payload.data(using: .utf8) else {
			XCTFail("Failed to encode JSON payload")
			return
		}

		let decoded = try JSONDecoder().decode(KolSettings.self, from: data)

		XCTAssertFalse(decoded.useDoubleTapOnly)
		XCTAssertFalse(decoded.doubleTapLockEnabled)
	}

	func testEncodeDecodeRoundTripPreservesNormalizedDoubleTapValues() throws {
		let settings = KolSettings(useDoubleTapOnly: true, doubleTapLockEnabled: false)
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(KolSettings.self, from: data)

		XCTAssertFalse(settings.useDoubleTapOnly)
		XCTAssertFalse(decoded.useDoubleTapOnly)
		XCTAssertEqual(decoded, settings)
	}

	// MARK: - Post-v1 Field Defaults

	func testMissingPostV1FieldsDecodeToDefaults() throws {
		// Minimal JSON with only required fields — all post-v1 fields should
		// decode to their defaults without crashing.
		let json = "{}"
		let data = json.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(KolSettings.self, from: data)

		// LLM fields
		XCTAssertFalse(decoded.llmPostProcessingEnabled)
		XCTAssertEqual(decoded.llmCustomRules, "")
		XCTAssertNil(decoded.llmPromptCode)
		XCTAssertNil(decoded.llmPromptMessaging)
		XCTAssertNil(decoded.llmPromptDocument)
		XCTAssertNil(decoded.llmPromptEmail)
		XCTAssertFalse(decoded.llmScreenContextEnabled)

		// Context engineering fields
		XCTAssertFalse(decoded.conversationContextEnabled)
		XCTAssertFalse(decoded.atMentionInsertionEnabled)
		XCTAssertFalse(decoded.ocrContextEnabled)

		// VAD
		XCTAssertTrue(decoded.vadSilenceDetectionEnabled)
	}

	private func loadFixture(named name: String) throws -> Data {
		guard let url = Bundle(for: KolSettingsMigrationTests.self).url(
			forResource: name,
			withExtension: "json"
		) else {
			XCTFail("Missing fixture \(name).json")
			throw NSError(domain: "Fixture", code: 0)
		}
		return try Data(contentsOf: url)
	}
}
