import ComposableArchitecture
import Inject
import SwiftUI

struct WordRemappingsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@FocusState private var isScratchpadFocused: Bool
	@State private var activeSection: ModificationSection = .removals


    var body: some View {
        Section("Text transforms") {
            Picker("Rule type", selection: $activeSection) {
                ForEach(ModificationSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            switch activeSection {
            case .removals:
                Toggle("Enable word removals", isOn: Binding(
                    get: { store.kolSettings.wordRemovalsEnabled },
                    set: { store.send(.setWordRemovalsEnabled($0)) }
                ))
                ForEach(store.kolSettings.wordRemovals) { removal in
                    if let binding = removalBinding(for: removal.id) {
                        HStack {
                            Toggle("Enable removal", isOn: binding.isEnabled).labelsHidden()
                            TextField("Regular expression", text: binding.pattern)
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.send(.removeWordRemoval(removal.id))
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Delete word removal")
                        }
                    }
                }
                Button("Add word removal", systemImage: "plus") { store.send(.addWordRemoval) }
            case .remappings:
                ForEach(store.kolSettings.wordRemappings) { remapping in
                    if let binding = remappingBinding(for: remapping.id) {
                        HStack {
                            Toggle("Enable replacement", isOn: binding.isEnabled).labelsHidden()
                            TextField("Match", text: binding.match)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                            TextField("Replacement", text: binding.replacement)
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.send(.removeWordRemapping(remapping.id))
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Delete word replacement")
                        }
                    }
                }
                Button("Add replacement", systemImage: "plus") { store.send(.addWordRemapping) }
            }
            Text("Word removals run first, followed by replacements.").settingsCaption()
        }
        Section("Test transforms") {
            TextField("Test input", text: $store.remappingScratchpadText)
                .focused($isScratchpadFocused)
                .onChange(of: isScratchpadFocused) { _, focused in
                    store.send(.setRemappingScratchpadFocused(focused))
                }
            LabeledContent("Preview", value: store.scratchpadPreviewText.isEmpty ? "No output" : store.scratchpadPreviewText)
                .textSelection(.enabled)
        }
        .onDisappear { store.send(.setRemappingScratchpadFocused(false)) }
    }

	private func removalBinding(for id: UUID) -> Binding<WordRemoval>? {
		guard store.kolSettings.wordRemovals.contains(where: { $0.id == id }) else { return nil }
		return Binding(
			get: {
				// Look up by id each time — index-based capture would go stale after deletions.
				guard let idx = store.kolSettings.wordRemovals.firstIndex(where: { $0.id == id }) else {
					return WordRemoval(pattern: "")
				}
				return store.kolSettings.wordRemovals[idx]
			},
			set: { store.send(.updateWordRemoval($0)) }
		)
	}

	private func remappingBinding(for id: UUID) -> Binding<WordRemapping>? {
		guard store.kolSettings.wordRemappings.contains(where: { $0.id == id }) else { return nil }
		return Binding(
			get: {
				// Look up by id each time — index-based capture would go stale after deletions.
				guard let idx = store.kolSettings.wordRemappings.firstIndex(where: { $0.id == id }) else {
					return WordRemapping(match: "", replacement: "")
				}
				return store.kolSettings.wordRemappings[idx]
			},
			set: { store.send(.updateWordRemapping($0)) }
		)
	}
}

private enum ModificationSection: String, CaseIterable, Identifiable {
	case removals
	case remappings

	var id: String { rawValue }

	var title: String {
		switch self {
		case .removals: "Word Removals"
		case .remappings: "Word Remappings"
		}
	}
}
