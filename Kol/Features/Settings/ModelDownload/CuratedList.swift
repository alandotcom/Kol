import ComposableArchitecture
import SwiftUI

struct CuratedList: View {
    @Bindable var store: StoreOf<ModelDownloadFeature>

    private var models: [CuratedModelInfo] {
        store.curatedModels.filter { store.showAllModels || $0.isParakeet }
    }

    var body: some View {
        Picker("Model", selection: Binding(
            get: {
                models.first(where: { $0.isSelected(forSetting: store.kolSettings.selectedModel) })?.internalName ?? store.kolSettings.selectedModel
            },
            set: { store.send(.selectModel($0)) }
        )) {
            ForEach(models) { model in
                Text("\(model.displayName) (\(model.storageSize))").tag(model.internalName)
            }
        }
        .disabled(store.isDownloading)
        .confirmationDialog("Delete the selected model?", isPresented: $showDeleteConfirmation) {
            Button("Delete model", role: .destructive) { store.send(.deleteSelectedModel) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Download the model again before using it for transcription.")
        }
        if store.curatedModels.contains(where: { !$0.isParakeet }) {
            Toggle("Show all models", isOn: Binding(
                get: { store.showAllModels },
                set: { _ in store.send(.toggleModelDisplay) }
            ))
        }
        if let model = store.curatedModels.first(where: { $0.isSelected(forSetting: store.kolSettings.selectedModel) }) {
            if store.isDownloading {
                ProgressView("Downloading \(store.downloadingModelName ?? model.displayName)…", value: store.downloadProgress)
                Button("Cancel download") { store.send(.cancelDownload) }
            } else if model.isDownloaded {
                LabeledContent("Status", value: "Downloaded")
                HStack {
                    Button("Show in Finder") { store.send(.openModelLocation) }
                    Button("Delete model…", role: .destructive) { showDeleteConfirmation = true }
                }
            } else {
                Button("Download \(model.displayName)") { store.send(.downloadSelectedModel) }
            }
        }
    }

    @State private var showDeleteConfirmation = false
}
