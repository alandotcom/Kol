import ComposableArchitecture
import Testing
@testable import KolCore

@MainActor
struct OpenRouterModelsFeatureTests {
    private let models = [OpenRouterModel(id: "example/new-model", name: "New Model")]

    @Test("Loading and refreshing preserve a saved model absent from the catalog")
    func selectionPreserved() async {
        var state = OpenRouterModelsFeature.State()
        state.currentModelID = "example/saved-model"
        state.highlightedModelID = state.currentModelID
        let models = models
        let store = TestStore(initialState: state) {
            OpenRouterModelsFeature()
        } withDependencies: {
            $0.openRouterModels.fetch = { models }
        }
        await store.send(.appeared) {
            $0.requestGeneration = 1
            $0.loadingGeneration = 1
        }
        await store.receive(.modelsLoaded(generation: 1, models: models)) {
            $0.models = models
            $0.loadingGeneration = nil
            $0.hasLoaded = true
        }
        #expect(store.state.currentModelID == "example/saved-model")
        #expect(!store.state.canChooseModel)
        await store.send(.refresh) {
            $0.requestGeneration = 2
            $0.loadingGeneration = 2
        }
        await store.receive(.modelsLoaded(generation: 2, models: models)) {
            $0.loadingGeneration = nil
        }
        #expect(store.state.currentModelID == "example/saved-model")
    }

    @Test("Failure retains the current model and cached catalog; retry clears the error")
    func failureAndRetry() async {
        var state = OpenRouterModelsFeature.State()
        state.currentModelID = "example/saved-model"
        state.models = models
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            OpenRouterModelsFeature()
        } withDependencies: {
            $0.openRouterModels.fetch = { throw OpenRouterModelsError.httpStatus(503) }
        }
        await store.send(.refresh) {
            $0.requestGeneration = 1
            $0.loadingGeneration = 1
        }
        await store.receive(.loadingFailed(generation: 1, message: "OpenRouter returned HTTP 503.")) {
            $0.loadingGeneration = nil
            $0.errorMessage = "OpenRouter returned HTTP 503."
        }
        #expect(store.state.currentModelID == "example/saved-model")
        #expect(store.state.models == models)
        store.dependencies.openRouterModels.fetch = { [] }
        await store.send(.refresh) {
            $0.requestGeneration = 2
            $0.loadingGeneration = 2
            $0.errorMessage = nil
        }
        await store.receive(.modelsLoaded(generation: 2, models: [])) {
            $0.models = []
            $0.loadingGeneration = nil
        }
        #expect(store.state.currentModelID == "example/saved-model")
    }

    @Test("Highlighting a row saves only after explicit confirmation")
    func explicitSelection() async {
        var state = OpenRouterModelsFeature.State()
        state.models = models
        state.currentModelID = "example/saved-model"
        let store = TestStore(initialState: state) { OpenRouterModelsFeature() }
        await store.send(.highlightModel("example/new-model")) {
            $0.highlightedModelID = "example/new-model"
        }
        #expect(store.state.currentModelID == "example/saved-model")
        await store.send(.chooseModel) {
            $0.currentModelID = "example/new-model"
        }
        await store.receive(.delegate(.modelSelected("example/new-model")))
    }

    @Test("Missing and stale selections cannot be confirmed")
    func invalidSelection() async {
        var state = OpenRouterModelsFeature.State()
        state.currentModelID = "example/saved-model"
        state.highlightedModelID = "example/saved-model"
        state.models = models
        let store = TestStore(initialState: state) { OpenRouterModelsFeature() }
        await store.send(.chooseModel)
        await store.send(.highlightModel(nil)) { $0.highlightedModelID = nil }
        await store.send(.chooseModel)
    }

    @Test("Duplicate loads and reopening a loaded catalog do not fetch again")
    func duplicateLoads() async {
        var state = OpenRouterModelsFeature.State()
        state.loadingGeneration = 1
        state.requestGeneration = 1
        let store = TestStore(initialState: state) { OpenRouterModelsFeature() }
        await store.send(.appeared)
        await store.send(.refresh)
        await store.send(.modelsLoaded(generation: 1, models: [])) {
            $0.loadingGeneration = nil
            $0.hasLoaded = true
        }
        await store.send(.appeared)
    }

    @Test("Dismissal cancels an active fetch and stale responses cannot replace the catalog")
    func cancellationAndStaleResponses() async {
        let store = TestStore(initialState: OpenRouterModelsFeature.State()) {
            OpenRouterModelsFeature()
        } withDependencies: {
            $0.openRouterModels.fetch = {
                try await Task.sleep(for: .seconds(60))
                return []
            }
        }
        await store.send(.appeared) {
            $0.requestGeneration = 1
            $0.loadingGeneration = 1
        }
        await store.send(.dismissed) { $0.loadingGeneration = nil }
        await store.send(.modelsLoaded(generation: 1, models: models))
        await store.send(.loadingFailed(generation: 1, message: "Old error"))
        await store.finish()
    }

    @Test("Search filters the catalog without changing the selection")
    func search() async {
        var state = OpenRouterModelsFeature.State()
        state.models = models
        state.highlightedModelID = "example/new-model"
        state.currentModelID = "example/saved-model"
        let store = TestStore(initialState: state) { OpenRouterModelsFeature() }
        await store.send(.setSearch("NEW")) { $0.search = "NEW" }
        #expect(store.state.filteredModels == models)
        #expect(store.state.canChooseModel)
        await store.send(.setSearch("absent")) { $0.search = "absent" }
        #expect(store.state.filteredModels.isEmpty)
        #expect(!store.state.canChooseModel)
        await store.send(.chooseModel)
        #expect(store.state.currentModelID == "example/saved-model")
    }
}
