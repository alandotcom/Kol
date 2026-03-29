import ComposableArchitecture
import Inject
import SwiftUI

struct WordRemappingsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@FocusState private var isScratchpadFocused: Bool
	@State private var activeSection: ModificationSection = .removals

	private var activeCount: Int {
		switch activeSection {
		case .removals:
			store.kolSettings.wordRemovals.filter(\.isEnabled).count
		case .remappings:
			store.kolSettings.wordRemappings.filter(\.isEnabled).count
		}
	}

	private var totalCount: Int {
		switch activeSection {
		case .removals: store.kolSettings.wordRemovals.count
		case .remappings: store.kolSettings.wordRemappings.count
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 24) {
			// Header
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Transforms")
						.font(.title2.bold())
					Text("Post-processing rules applied to transcriptions")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				Spacer()

				Button {
					switch activeSection {
					case .removals: store.send(.addWordRemoval)
					case .remappings: store.send(.addWordRemapping)
					}
				} label: {
					Label("Add Transform", systemImage: "plus")
						.font(.subheadline.weight(.medium))
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.regular)
			}

			// Active count badge
			HStack(spacing: 8) {
				HStack(spacing: 6) {
					Circle()
						.fill(Color.green)
						.frame(width: 6, height: 6)
					Text("\(activeCount) active")
						.font(.caption.weight(.medium))
						.foregroundStyle(.green)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
				.background(Color.green.opacity(0.12))
				.clipShape(RoundedRectangle(cornerRadius: 8))

				Text("of \(totalCount) transforms")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			// Section picker
			Picker("Modification Type", selection: $activeSection) {
				ForEach(ModificationSection.allCases) { section in
					Text(section.title).tag(section)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			// Transform list
			switch activeSection {
			case .removals: removalsSection
			case .remappings: remappingsSection
			}

			// Scratchpad
			GlassCard {
				HStack(spacing: 16) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Test Input")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						TextField("Say something…", text: $store.remappingScratchpadText)
							.textFieldStyle(.roundedBorder)
							.focused($isScratchpadFocused)
							.onChange(of: isScratchpadFocused) { _, newValue in
								store.send(.setRemappingScratchpadFocused(newValue))
							}
					}
					VStack(alignment: .leading, spacing: 4) {
						Text("Preview")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						Text(previewText.isEmpty ? "—" : previewText)
							.font(.body)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 8)
							.padding(.vertical, 6)
							.background(GlassColors.dropdownBackground)
							.clipShape(RoundedRectangle(cornerRadius: 6))
					}
				}
			}

			// Pro Tip
			HStack(spacing: 16) {
				Image(systemName: "sparkles")
					.font(.title3)
					.foregroundStyle(.blue)
					.frame(width: 40, height: 40)
					.background(Color.blue.opacity(0.1))
					.clipShape(RoundedRectangle(cornerRadius: 12))

				VStack(alignment: .leading, spacing: 4) {
					Text("Pro Tip")
						.font(.subheadline.weight(.medium))
					Text("Transforms are applied in sequence. Word removals run first, then remappings.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.padding(16)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.blue.opacity(0.04))
			.clipShape(RoundedRectangle(cornerRadius: 12))
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.strokeBorder(Color.blue.opacity(0.15), lineWidth: 0.5)
			)
		}
		.onDisappear {
			store.send(.setRemappingScratchpadFocused(false))
		}
		.enableInjection()
	}

	private var removalsSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			Toggle(
				"Enable Word Removals",
				isOn: Binding(
					get: { store.kolSettings.wordRemovalsEnabled },
					set: { store.send(.setWordRemovalsEnabled($0)) }
				)
			)
			.toggleStyle(.switch)

			ForEach(store.kolSettings.wordRemovals) { removal in
				if let binding = removalBinding(for: removal.id) {
					TransformCard(
						icon: "strikethrough",
						iconColor: .orange,
						isEnabled: binding.wrappedValue.isEnabled,
						onToggle: { binding.wrappedValue.isEnabled.toggle() },
						onDelete: { store.send(.removeWordRemoval(removal.id)) }
					) {
						TextField("Regex Pattern", text: binding.pattern)
							.textFieldStyle(.roundedBorder)
							.font(.subheadline)
					}
				}
			}
		}
	}

	private var remappingsSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			ForEach(store.kolSettings.wordRemappings) { remapping in
				if let binding = remappingBinding(for: remapping.id) {
					TransformCard(
						icon: "arrow.right.arrow.left",
						iconColor: .purple,
						isEnabled: binding.wrappedValue.isEnabled,
						onToggle: { binding.wrappedValue.isEnabled.toggle() },
						onDelete: { store.send(.removeWordRemapping(remapping.id)) }
					) {
						HStack(spacing: 8) {
							TextField("Match", text: binding.match)
								.textFieldStyle(.roundedBorder)
								.font(.subheadline)
							Image(systemName: "arrow.right")
								.foregroundStyle(.secondary)
								.font(.caption)
							TextField("Replace", text: binding.replacement)
								.textFieldStyle(.roundedBorder)
								.font(.subheadline)
						}
					}
				}
			}
		}
	}

	private func removalBinding(for id: UUID) -> Binding<WordRemoval>? {
		guard store.kolSettings.wordRemovals.contains(where: { $0.id == id }) else { return nil }
		return Binding(
			get: {
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
				guard let idx = store.kolSettings.wordRemappings.firstIndex(where: { $0.id == id }) else {
					return WordRemapping(match: "", replacement: "")
				}
				return store.kolSettings.wordRemappings[idx]
			},
			set: { store.send(.updateWordRemapping($0)) }
		)
	}

	private var previewText: String {
		var output = store.remappingScratchpadText
		if store.kolSettings.wordRemovalsEnabled {
			output = WordRemovalApplier.apply(output, removals: store.kolSettings.wordRemovals)
		}
		output = WordRemappingApplier.apply(output, remappings: store.kolSettings.wordRemappings)
		return output
	}
}

/// A transform card with icon, content, and toggle. Delete appears on hover only.
private struct TransformCard<Content: View>: View {
	let icon: String
	let iconColor: Color
	let isEnabled: Bool
	let onToggle: () -> Void
	let onDelete: () -> Void
	let content: Content

	@State private var isHovered = false

	init(
		icon: String,
		iconColor: Color,
		isEnabled: Bool,
		onToggle: @escaping () -> Void,
		onDelete: @escaping () -> Void,
		@ViewBuilder content: () -> Content
	) {
		self.icon = icon
		self.iconColor = iconColor
		self.isEnabled = isEnabled
		self.onToggle = onToggle
		self.onDelete = onDelete
		self.content = content()
	}

	var body: some View {
		HStack(spacing: 16) {
			// Icon
			Image(systemName: icon)
				.font(.system(size: 18))
				.foregroundStyle(isEnabled ? iconColor : .secondary)
				.frame(width: 44, height: 44)
				.background(isEnabled ? iconColor.opacity(0.12) : Color.gray.opacity(0.06))
				.clipShape(RoundedRectangle(cornerRadius: 12))

			// Content
			content
				.frame(maxWidth: .infinity)

			// Delete (hover only)
			Button(action: onDelete) {
				Image(systemName: "trash")
					.font(.system(size: 13))
					.foregroundStyle(.red.opacity(0.5))
			}
			.buttonStyle(.plain)
			.opacity(isHovered ? 1 : 0)
			.animation(.easeInOut(duration: 0.15), value: isHovered)

			// Toggle
			Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
				.labelsHidden()
				.toggleStyle(.switch)
		}
		.padding(20)
		.opacity(isEnabled ? 1 : 0.5)
		.background(GlassColors.cardBackground)
		.clipShape(RoundedRectangle(cornerRadius: 16))
		.overlay(
			RoundedRectangle(cornerRadius: 16)
				.strokeBorder(GlassColors.cardBorder, lineWidth: 0.5)
		)
		.shadow(color: .black.opacity(0.06), radius: 4, y: 2)
		.shadow(color: .black.opacity(0.06), radius: 12, y: 8)
		.onHover { isHovered = $0 }
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
