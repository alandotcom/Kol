import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let logger = HexLog.llm

@DependencyClient
struct LLMPostProcessingClient: Sendable {
	var process: @Sendable (
		_ context: PostProcessingContext,
		_ config: LLMProviderConfig,
		_ apiKey: String
	) async throws -> String
}

extension LLMPostProcessingClient: DependencyKey {
	static var liveValue: Self {
		Self(
			process: { context, config, apiKey in
				let systemPrompt = PromptAssembler.systemPrompt(
					language: context.inputLanguage,
					sourceApp: context.sourceApp,
					customRules: context.customRules,
					appContextOverrides: context.appContextOverrides,
					screenContext: context.screenContext
				)
				let userMessage = PromptAssembler.userMessage(text: context.text)

				logger.notice("LLM sourceApp: \(context.sourceApp ?? "nil", privacy: .public)")
				logger.notice("LLM screenContext length: \(context.screenContext?.count ?? 0)")
				logger.notice("LLM system prompt preview: \(String(systemPrompt.suffix(200)), privacy: .public)")

				let url = URL(string: "\(config.baseURL)/chat/completions")!
				var request = URLRequest(url: url)
				request.httpMethod = "POST"
				request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
				request.setValue("application/json", forHTTPHeaderField: "Content-Type")
				request.timeoutInterval = 5

				let body: [String: Any] = [
					"model": config.modelName,
					"messages": [
						["role": "system", "content": systemPrompt],
						["role": "user", "content": userMessage],
					],
					"temperature": 0,
					"max_tokens": 4096,
				]
				request.httpBody = try JSONSerialization.data(withJSONObject: body)

				let startTime = Date()
				let (data, response) = try await URLSession.shared.data(for: request)
				let elapsed = Date().timeIntervalSince(startTime)

				guard let httpResponse = response as? HTTPURLResponse else {
					throw LLMError.invalidResponse
				}
				guard httpResponse.statusCode == 200 else {
					let body = String(data: data, encoding: .utf8) ?? ""
					logger.error("LLM API error \(httpResponse.statusCode): \(body)")
					throw LLMError.apiError(statusCode: httpResponse.statusCode, body: body)
				}

				guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
					  let choices = json["choices"] as? [[String: Any]],
					  let first = choices.first,
					  let message = first["message"] as? [String: Any],
					  let content = message["content"] as? String
				else {
					throw LLMError.invalidResponse
				}

				var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
				// Strip outer quotes if the LLM wrapped the response
				if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 1 {
					trimmed = String(trimmed.dropFirst().dropLast())
						.trimmingCharacters(in: .whitespacesAndNewlines)
				}
				// Treat EMPTY sentinel as empty string
				if trimmed == "EMPTY" { trimmed = "" }
				logger.info("LLM post-processing took \(String(format: "%.0f", elapsed * 1000))ms (\(config.modelName))")

				return trimmed.isEmpty ? context.text : trimmed
			}
		)
	}
}

enum LLMError: Error, LocalizedError {
	case invalidResponse
	case apiError(statusCode: Int, body: String)

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			return "Invalid response from LLM API"
		case .apiError(let code, let body):
			return "LLM API error \(code): \(body)"
		}
	}
}

extension DependencyValues {
	var llmPostProcessing: LLMPostProcessingClient {
		get { self[LLMPostProcessingClient.self] }
		set { self[LLMPostProcessingClient.self] = newValue }
	}
}
