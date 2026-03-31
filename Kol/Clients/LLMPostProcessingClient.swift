import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.llm

@DependencyClient
struct LLMPostProcessingClient: Sendable {
	var process: @Sendable (
		_ context: PostProcessingContext,
		_ config: LLMProviderConfig,
		_ apiKey: String
	) async throws -> LLMProcessingResult
}

extension LLMPostProcessingClient: DependencyKey {
	private static let llmSession: URLSession = {
		let config = URLSessionConfiguration.default
		config.waitsForConnectivity = true
		config.allowsExpensiveNetworkAccess = false
		config.timeoutIntervalForRequest = 5
		config.timeoutIntervalForResource = 30
		return URLSession(configuration: config)
	}()

	static var liveValue: Self {
		Self(
			process: { context, config, apiKey in
				let systemPrompt = PromptAssembler.systemPrompt(
					language: context.inputLanguage,
					sourceApp: context.sourceApp,
					customRules: context.customRules,
					appContextOverrides: context.appContextOverrides,
					ideContext: context.ideContext,
					screenContext: context.screenContext,
					structuredContext: context.structuredContext,
					vocabularyHints: context.vocabularyHints,
					conversationContext: context.conversationContext,
					resolvedCategory: context.resolvedCategory
				)
				let userMessage = PromptAssembler.userMessage(text: context.text)

				logger.notice("LLM sourceApp: \(context.sourceApp ?? "nil", privacy: .public)")
				logger.notice("LLM screenContext length: \(context.screenContext?.count ?? 0)")
				let vocabPreview = context.vocabularyHints?.joined(separator: ", ") ?? "(none)"
				logger.notice("LLM vocabulary hints: \(vocabPreview, privacy: .public)")
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
				let (data, response) = try await Self.llmSession.data(for: request)
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

				// Parse token usage from response
				let usage = json["usage"] as? [String: Any]
				let promptTokens = usage?["prompt_tokens"] as? Int
				let completionTokens = usage?["completion_tokens"] as? Int

				var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
				// Strip outer quotes if the LLM wrapped the response
				if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 1 {
					trimmed = String(trimmed.dropFirst().dropLast())
						.trimmingCharacters(in: .whitespacesAndNewlines)
				}
				// Treat EMPTY sentinel as empty string
				if trimmed == "EMPTY" { trimmed = "" }

				let latencyMs = Int(elapsed * 1000)
				logger.info("LLM post-processing took \(latencyMs)ms (\(config.modelName))")

				let finalText = trimmed.isEmpty ? context.text : trimmed
				let metadata = LLMMetadata(
					originalText: context.text,
					model: config.modelName,
					latencyMs: latencyMs,
					promptTokens: promptTokens,
					completionTokens: completionTokens
				)
				return LLMProcessingResult(text: finalText, metadata: metadata)
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
