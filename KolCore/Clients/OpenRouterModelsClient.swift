import Dependencies
import DependenciesMacros
import Foundation

public struct OpenRouterModel: Equatable, Identifiable, Sendable {
	public let id: String
	public let name: String

	public init(id: String, name: String) {
		self.id = id
		self.name = name
	}

	public func matches(_ search: String) -> Bool {
		let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
		return query.isEmpty || name.localizedCaseInsensitiveContains(query) || id.localizedCaseInsensitiveContains(query)
	}
}

public enum OpenRouterModelsError: Error, Equatable, LocalizedError {
	case invalidResponse
	case httpStatus(Int)
	case invalidCatalog

	public var errorDescription: String? {
		switch self {
		case .invalidResponse: return "OpenRouter returned an invalid response."
		case let .httpStatus(status): return "OpenRouter returned HTTP \(status)."
		case .invalidCatalog: return "OpenRouter returned an unreadable model catalog."
		}
	}
}

@DependencyClient
public struct OpenRouterModelsClient: Sendable {
	public var fetch: @Sendable () async throws -> [OpenRouterModel]
}

extension OpenRouterModelsClient: DependencyKey {
	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.waitsForConnectivity = false
		configuration.timeoutIntervalForRequest = 15
		configuration.timeoutIntervalForResource = 30
		return URLSession(configuration: configuration)
	}()

	public static var liveValue: Self {
		Self(fetch: {
			try await fetchModels { request in
				try await session.data(for: request)
			}
		})
	}

	static func fetchModels(
		using load: @Sendable (URLRequest) async throws -> (Data, URLResponse)
	) async throws -> [OpenRouterModel] {
		let url = URL(string: "https://openrouter.ai/api/v1/models")!
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		let (data, response) = try await load(request)
		guard let response = response as? HTTPURLResponse else {
			throw OpenRouterModelsError.invalidResponse
		}
		guard (200..<300).contains(response.statusCode) else {
			throw OpenRouterModelsError.httpStatus(response.statusCode)
		}
		return try decodeCatalog(data)
	}

	static func decodeCatalog(_ data: Data) throws -> [OpenRouterModel] {
		struct Catalog: Decodable {
			struct Model: Decodable {
				struct Architecture: Decodable {
					let input_modalities: [String]?
					let output_modalities: [String]?
				}
				let id: String
				let name: String
				let architecture: Architecture?
			}
			let data: [Model]
		}

		let catalog: Catalog
		do {
			catalog = try JSONDecoder().decode(Catalog.self, from: data)
		} catch {
			throw OpenRouterModelsError.invalidCatalog
		}
		var seenIDs = Set<String>()
		return catalog.data.compactMap { model in
			guard model.architecture?.input_modalities?.contains("text") == true,
				model.architecture?.output_modalities?.contains("text") == true,
				!model.id.isEmpty, !model.name.isEmpty,
				seenIDs.insert(model.id).inserted else { return nil }
			return OpenRouterModel(id: model.id, name: model.name)
		}.sorted {
			let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
			return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
		}
	}
}

public extension DependencyValues {
	var openRouterModels: OpenRouterModelsClient {
		get { self[OpenRouterModelsClient.self] }
		set { self[OpenRouterModelsClient.self] = newValue }
	}
}
