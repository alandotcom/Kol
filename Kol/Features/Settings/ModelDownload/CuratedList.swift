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

	private func isSelected(_ model: CuratedModelInfo) -> Bool {
		if model.isQwen {
			return model.isSelected(forSetting: store.kolSettings.selectedHebrewModel)
		}
		return model.isSelected(forSetting: store.kolSettings.selectedModel)
	}

	/// Returns the model to display as "selected" in a dropdown group.
	/// Priority: globally selected model (if in this group) → first downloaded model → first model.
	private func displayedModel(in models: [CuratedModelInfo]) -> CuratedModelInfo? {
		models.first { isSelected($0) }
			?? models.first { $0.isDownloaded }
			?? models.first
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			ModelDropdown(
				label: "ENGLISH MODEL",
				models: englishModels,
				selectedModel: displayedModel(in: englishModels),
				isDownloading: store.isDownloading,
				downloadingName: store.downloadingModelName,
				downloadProgress: store.downloadProgress,
				isSelected: isSelected,
				onSelect: { name in
					store.send(.selectModel(name))
				},
				onDownload: {
					store.send(.downloadSelectedModel)
				}
			)

			ModelDropdown(
				label: "HEBREW MODEL",
				models: hebrewModels,
				selectedModel: displayedModel(in: hebrewModels),
				isDownloading: store.isDownloading,
				downloadingName: store.downloadingModelName,
				downloadProgress: store.downloadProgress,
				isSelected: isSelected,
				onSelect: { name in
					store.send(.selectHebrewModel(name))
				},
				onDownload: {
					store.send(.downloadSelectedHebrewModel)
				}
			)

			Text("Kol switches automatically based on your keyboard layout.")
				.font(.system(size: 13))
				.foregroundStyle(.secondary)

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

// MARK: - Custom Dropdown

private struct ModelDropdown: View {
	let label: String
	let models: [CuratedModelInfo]
	let selectedModel: CuratedModelInfo?
	let isDownloading: Bool
	let downloadingName: String?
	let downloadProgress: Double
	let isSelected: (CuratedModelInfo) -> Bool
	let onSelect: (String) -> Void
	let onDownload: () -> Void

	@State private var isOpen = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			// Label
			Text(label)
				.font(.system(size: 12, weight: .medium))
				.foregroundStyle(.secondary)
				.tracking(0.5)

			// Dropdown trigger button
			Button {
				withAnimation(.easeInOut(duration: 0.2)) {
					isOpen.toggle()
				}
			} label: {
				HStack {
					if let model = selectedModel {
						Text(model.displayName)
							.font(.body.weight(.medium))
						Text(model.storageSize)
							.font(.system(size: 13))
							.foregroundStyle(.secondary)
					} else {
						Text("Select a model")
							.foregroundStyle(.secondary)
					}
					Spacer()
					Image(systemName: isOpen ? "chevron.up" : "chevron.down")
						.font(.system(size: 13))
						.foregroundStyle(.secondary)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				.background(GlassColors.dropdownBackground)
				.clipShape(RoundedRectangle(cornerRadius: 12))
				.overlay(
					RoundedRectangle(cornerRadius: 12)
						.strokeBorder(GlassColors.dropdownBorder, lineWidth: 0.5)
				)
			}
			.buttonStyle(.plain)

			// Expanded dropdown panel
			if isOpen {
				VStack(spacing: 0) {
					ForEach(models) { model in
						ModelRow(
							model: model,
							selected: isSelected(model),
							isDownloading: isDownloading && downloadingName == model.internalName,
							downloadProgress: downloadProgress
						) {
							onSelect(model.internalName)
							if !model.isDownloaded {
								onDownload()
							}
							withAnimation(.easeInOut(duration: 0.2)) {
								isOpen = false
							}
						}
					}
				}
				.padding(6)
				.background(GlassColors.dropdownPanel)
				.clipShape(RoundedRectangle(cornerRadius: 12))
				.overlay(
					RoundedRectangle(cornerRadius: 12)
						.strokeBorder(GlassColors.dropdownBorder, lineWidth: 0.5)
				)
				.shadow(color: .black.opacity(0.15), radius: 12, y: 4)
				.transition(.opacity.combined(with: .move(edge: .top)))
			}
		}
	}
}

private struct ModelRow: View {
	let model: CuratedModelInfo
	let selected: Bool
	let isDownloading: Bool
	let downloadProgress: Double
	let onTap: () -> Void

	@State private var isHovered = false

	var body: some View {
		Button(action: onTap) {
			HStack(spacing: 12) {
				// Radio circle
				ZStack {
					Circle()
						.strokeBorder(selected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
						.frame(width: 18, height: 18)
					if selected {
						Circle()
							.fill(Color.blue)
							.frame(width: 18, height: 18)
						Image(systemName: "checkmark")
							.font(.system(size: 10, weight: .bold))
							.foregroundStyle(.white)
					}
				}

				// Model name
				Text(model.displayName)
					.font(.body.weight(.medium))

				Spacer()

				// Size
				Text(model.storageSize)
					.font(.system(size: 13))
					.foregroundStyle(.secondary)

				// Status icon
				if isDownloading {
					ProgressView(value: downloadProgress)
						.progressViewStyle(.circular)
						.controlSize(.small)
						.frame(width: 18, height: 18)
				} else if model.isDownloaded {
					Image(systemName: "checkmark")
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(.green)
				} else {
					Image(systemName: "arrow.down.circle")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(
				RoundedRectangle(cornerRadius: 8)
					.fill(isHovered ? Color.black.opacity(0.04) : Color.clear)
			)
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
	}
}
