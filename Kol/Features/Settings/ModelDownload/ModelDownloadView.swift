import ComposableArchitecture
import SwiftUI

public struct ModelDownloadView: View {
    @Bindable var store: StoreOf<ModelDownloadFeature>
    var shouldFlash: Bool = false

    public init(store: StoreOf<ModelDownloadFeature>, shouldFlash: Bool = false) {
        self.store = store
        self.shouldFlash = shouldFlash
    }

    public var body: some View {
        Group {
            if !store.anyModelDownloaded {
                Label("Download a model to start transcribing", systemImage: "arrow.down.circle")
                Text("Speech recognition runs locally after the download finishes.").settingsCaption()
            }
            CuratedList(store: store)
            if let error = store.downloadError ?? store.modelBootstrapState.lastError {
                Label("Download failed", systemImage: "exclamationmark.triangle")
                Text(error).foregroundStyle(.secondary)
            }
        }
        .task {
            if store.availableModels.isEmpty { store.send(.fetchModels) }
        }
    }
}
