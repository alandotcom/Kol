import Foundation
import XCTest
@testable import KolCore

final class OpenRouterModelsClientTests: XCTestCase {
    private static let catalog = Data(#"""
    {"data":[
      {"id":"example/zeta","name":"Zeta","architecture":{"input_modalities":["text"],"output_modalities":["text"]}},
      {"id":"example/alpha","name":"Alpha","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}},
      {"id":"example/audio","name":"Audio","architecture":{"input_modalities":["audio"],"output_modalities":["text"]}},
      {"id":"example/image","name":"Image","architecture":{"input_modalities":["text"],"output_modalities":["image"]}},
      {"id":"example/unknown","name":"Unknown"},
      {"id":"example/incomplete","name":"Incomplete","architecture":{"input_modalities":["text"]}},
      {"id":"example/alpha","name":"Duplicate","architecture":{"input_modalities":["text"],"output_modalities":["text"]}}
    ]}
    """#.utf8)

    func testPublicRequestAndTextModelFiltering() async throws {
        let models = try await OpenRouterModelsClient.fetchModels { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.httpBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Self.catalog, response)
        }
        XCTAssertEqual(models, [
            OpenRouterModel(id: "example/alpha", name: "Alpha"),
            OpenRouterModel(id: "example/zeta", name: "Zeta"),
        ])
    }

    func testHTTPFailureIsReportedBeforeDecoding() async {
        do {
            _ = try await OpenRouterModelsClient.fetchModels { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (Data("unavailable".utf8), response)
            }
            XCTFail("Expected an HTTP error")
        } catch {
            XCTAssertEqual(error as? OpenRouterModelsError, .httpStatus(503))
        }
    }

    func testNonHTTPResponseIsRejected() async {
        do {
            _ = try await OpenRouterModelsClient.fetchModels { request in
                (Self.catalog, URLResponse(url: request.url!, mimeType: "application/json", expectedContentLength: 0, textEncodingName: nil))
            }
            XCTFail("Expected an invalid response error")
        } catch {
            XCTAssertEqual(error as? OpenRouterModelsError, .invalidResponse)
        }
    }

    func testNetworkFailurePropagates() async {
        do {
            _ = try await OpenRouterModelsClient.fetchModels { _ in
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Expected a network error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testMalformedCatalogIsRejectedAndEmptyCatalogAccepted() throws {
        for json in ["invalid json", #"{"data":[{"id":"example/missing-name"}]}"#, #"{"models":[]}"#] {
            XCTAssertThrowsError(try OpenRouterModelsClient.decodeCatalog(Data(json.utf8))) { error in
                XCTAssertEqual(error as? OpenRouterModelsError, .invalidCatalog)
            }
        }
        XCTAssertEqual(try OpenRouterModelsClient.decodeCatalog(Data(#"{"data":[]}"#.utf8)), [])
    }

    func testSearchMatchesNamesAndIDsIgnoringCaseAndWhitespace() {
        let model = OpenRouterModel(id: "example/text-model", name: "Example Model")
        XCTAssertTrue(model.matches("EXAMPLE MODEL"))
        XCTAssertTrue(model.matches(" TEXT-MODEL "))
        XCTAssertTrue(model.matches("  "))
        XCTAssertFalse(model.matches("other"))
    }
}
