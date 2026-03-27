import ComposableArchitecture
import Inject
import SwiftUI

struct CuratedList: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<ModelDownloadFeature>

	private var englishModels: [CuratedModelInfo] {
		store.curatedModels.filter { $0.isParakeet }
	}

	private var hebrewModels: [CuratedModelInfo] {
		store.curatedModels.filter { $0.isQwen }
	}

	private var hiddenModels: [CuratedModelInfo] {
		store.curatedModels.filter { !$0.isParakeet && !$0.isQwen }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			// English models
			Text("English Model")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			ForEach(englishModels) { model in
				CuratedRow(store: store, model: model)
			}

			// Hebrew models
			Text("Hebrew Model")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.padding(.top, 4)
			ForEach(hebrewModels) { model in
				CuratedRow(store: store, model: model)
			}

			// Auto-switching explanation
			Text("Hex switches automatically based on your keyboard layout.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.top, 2)

			// Show "Show more"/"Show less" button for WhisperKit models
			if !hiddenModels.isEmpty {
				Button(action: { store.send(.toggleModelDisplay) }) {
					HStack {
						Spacer()
						Text(store.showAllModels ? "Show less" : "Show more")
							.font(.subheadline)
						Spacer()
					}
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
			}

			if store.showAllModels {
				ForEach(hiddenModels) { model in
					CuratedRow(store: store, model: model)
				}
			}
		}
		.enableInjection()
	}
}
