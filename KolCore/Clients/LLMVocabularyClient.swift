import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.vocabulary

@DependencyClient
public struct LLMVocabularyClient: Sendable {
	public var extractNames: @Sendable (
		_ screenText: String,
		_ conversationID: String?,
		_ config: LLMProviderConfig,
		_ apiKey: String
	) async throws -> [String]
}

extension LLMVocabularyClient: DependencyKey {
	/// Tighter timeout than post-processing — this is fire-and-forget.
	private static let session: URLSession = {
		let config = URLSessionConfiguration.default
		config.waitsForConnectivity = false
		config.allowsExpensiveNetworkAccess = false
		config.timeoutIntervalForRequest = 3
		config.timeoutIntervalForResource = 10
		return URLSession(configuration: config)
	}()

	private static let systemPrompt = """
	Extract proper nouns, person names, company names, and product names from this text. \
	Return ONLY a comma-separated list. If none found, return EMPTY. \
	Do not include common English words, code keywords, or generic terms.
	"""

	/// Maximum total characters in the response before truncation.
	private static let maxResponseChars = 140

	public static var liveValue: Self {
		Self(
			extractNames: { screenText, conversationID, config, apiKey in
				var userMessage = ""
				if let id = conversationID, !id.isEmpty {
					userMessage += id + "\n"
				}
				userMessage += screenText

				guard !config.baseURL.isEmpty,
					  let url = URL(string: "\(config.baseURL)/chat/completions")
				else {
					throw LLMError.invalidConfiguration("Base URL is empty or malformed: \(config.baseURL)")
				}
				var request = URLRequest(url: url)
				request.httpMethod = "POST"
				request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
				request.setValue("application/json", forHTTPHeaderField: "Content-Type")
				guard !config.modelName.isEmpty else {
					throw LLMError.invalidConfiguration("Model name is empty")
				}

				let body: [String: Any] = [
					"model": config.modelName,
					"messages": [
						["role": "system", "content": systemPrompt],
						["role": "user", "content": userMessage],
					],
					"temperature": 0,
					"max_tokens": 60,
				]
				request.httpBody = try JSONSerialization.data(withJSONObject: body)

				let startTime = Date()
				let (data, response) = try await session.data(for: request)
				let elapsed = Date().timeIntervalSince(startTime)

				guard let httpResponse = response as? HTTPURLResponse,
					  httpResponse.statusCode == 200
				else {
					let code = (response as? HTTPURLResponse)?.statusCode ?? -1
					logger.error("LLM vocabulary extraction API error \(code)")
					throw LLMError.apiError(statusCode: code, body: "")
				}

				guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
					  let choices = json["choices"] as? [[String: Any]],
					  let first = choices.first,
					  let message = first["message"] as? [String: Any],
					  let content = message["content"] as? String
				else {
					throw LLMError.invalidResponse
				}

				let names = parseResponse(content)
				let latencyMs = Int(elapsed * 1000)
				logger.info("LLM vocabulary extraction took \(latencyMs)ms, extracted \(names.count) names: \(names.joined(separator: ", "), privacy: .private)")
				return names
			}
		)
	}

	/// Parse LLM response into a list of names with safety caps.
	static func parseResponse(_ content: String) -> [String] {
		let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty || trimmed == "EMPTY" { return [] }

		// Cap total response length, dropping the last partial item
		let capped: String
		if trimmed.count > maxResponseChars {
			let truncated = String(trimmed.prefix(maxResponseChars))
			if let lastComma = truncated.lastIndex(of: ",") {
				capped = String(truncated[..<lastComma])
			} else {
				capped = truncated
			}
		} else {
			capped = trimmed
		}

		// Normalize newlines to commas so "Alice\nBob\nCharlie" is split correctly
		return capped
			.replacingOccurrences(of: "\n", with: ",")
			.split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty && $0.count <= 40 }
			.filter { !VocabularyExtractor.looksLikeGarbage($0) }
	}
}

public extension DependencyValues {
	var llmVocabulary: LLMVocabularyClient {
		get { self[LLMVocabularyClient.self] }
		set { self[LLMVocabularyClient.self] = newValue }
	}
}
