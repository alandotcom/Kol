import ComposableArchitecture
import Foundation

@Reducer
public struct OpenRouterModelsFeature {
	public init() {}

	@ObservableState
	public struct State: Equatable {
		public var models: [OpenRouterModel] = []
		public var search = ""
		public var currentModelID = ""
		public var highlightedModelID: String?
		public var errorMessage: String?
		public var hasLoaded = false
		public var requestGeneration: UInt64 = 0
		public var loadingGeneration: UInt64?

		public init() {}

		public var isLoading: Bool { loadingGeneration != nil }
		public var filteredModels: [OpenRouterModel] { models.filter { $0.matches(search) } }
		public var canChooseModel: Bool {
			guard let highlightedModelID else { return false }
			return filteredModels.contains { $0.id == highlightedModelID }
		}
	}

	public enum Action: Equatable {
		case appeared
		case refresh
		case dismissed
		case setSearch(String)
		case highlightModel(String?)
		case chooseModel
		case modelsLoaded(generation: UInt64, models: [OpenRouterModel])
		case loadingFailed(generation: UInt64, message: String)
		case delegate(Delegate)

		public enum Delegate: Equatable {
			case modelSelected(String)
		}
	}

	private enum CancelID { case fetch }
	@Dependency(\.openRouterModels) var openRouterModels

	public var body: some ReducerOf<Self> {
		Reduce { state, action in
			switch action {
			case .appeared:
				guard !state.hasLoaded else { return .none }
				return loadModels(state: &state)

			case .refresh:
				return loadModels(state: &state)

			case .dismissed:
				state.loadingGeneration = nil
				return .cancel(id: CancelID.fetch)

			case let .setSearch(search):
				state.search = search
				return .none

			case let .highlightModel(id):
				state.highlightedModelID = id
				return .none

			case .chooseModel:
				guard state.canChooseModel, let id = state.highlightedModelID else { return .none }
				state.currentModelID = id
				return .send(.delegate(.modelSelected(id)))

			case let .modelsLoaded(generation, models):
				guard state.loadingGeneration == generation else { return .none }
				state.models = models
				state.loadingGeneration = nil
				state.hasLoaded = true
				state.errorMessage = nil
				return .none

			case let .loadingFailed(generation, message):
				guard state.loadingGeneration == generation else { return .none }
				state.loadingGeneration = nil
				state.errorMessage = message
				return .none

			case .delegate:
				return .none
			}
		}
	}

	private func loadModels(state: inout State) -> Effect<Action> {
		guard !state.isLoading else { return .none }
		state.requestGeneration += 1
		let generation = state.requestGeneration
		state.loadingGeneration = generation
		state.errorMessage = nil
		return .run { [openRouterModels] send in
			do {
				let models = try await openRouterModels.fetch()
				try Task.checkCancellation()
				await send(.modelsLoaded(generation: generation, models: models))
			} catch is CancellationError {
				return
			} catch {
				guard !Task.isCancelled else { return }
				await send(.loadingFailed(generation: generation, message: error.localizedDescription))
			}
		}.cancellable(id: CancelID.fetch, cancelInFlight: true)
	}
}
