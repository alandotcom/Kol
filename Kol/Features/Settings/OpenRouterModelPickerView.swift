import ComposableArchitecture
import KolCore
import SwiftUI

struct OpenRouterModelPickerView: View {
    @Bindable var store: StoreOf<OpenRouterModelsFeature>
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose an OpenRouter model").font(.headline)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { store.send(.refresh) }
                    .disabled(store.isLoading)
            }
            if !store.currentModelID.isEmpty {
                LabeledContent("Current model", value: store.currentModelID)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            TextField("Search by model name or ID", text: Binding(
                get: { store.search },
                set: { store.send(.setSearch($0)) }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Search OpenRouter models")

            if store.isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading models…").foregroundStyle(.secondary)
                }
            }
            if let error = store.errorMessage {
                HStack(alignment: .top) {
                    Text("Could not load models. \(error)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { store.send(.refresh) }
                }
            }

            List(selection: Binding(
                get: { store.highlightedModelID },
                set: { store.send(.highlightModel($0)) }
            )) {
                ForEach(store.filteredModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.name)
                            Text(model.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.id == store.currentModelID {
                            Image(systemName: "checkmark").accessibilityLabel("Current model")
                        }
                    }
                    .tag(model.id)
                }
            }
            .overlay {
                if store.filteredModels.isEmpty && !store.isLoading && store.errorMessage == nil {
                    Text(store.models.isEmpty ? "No text models are available." : "No models match your search.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Link("OpenRouter model catalog", destination: URL(string: "https://openrouter.ai/models")!)
                    .font(.caption)
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Choose") { store.send(.chooseModel) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.canChooseModel)
            }
        }
        .padding(20)
        .frame(width: 580, height: 540)
    }
}
