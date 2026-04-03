import AppKit
import ComposableArchitecture
import Inject
import SwiftUI

// MARK: - Transcript Card View

struct TranscriptView: View {
	let transcript: Transcript
	let isPlaying: Bool
	let onPlay: () -> Void
	let onCopy: () -> Void
	let onDelete: () -> Void

	@State private var appIcon: NSImage?

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Metadata bar
			HStack(spacing: 6) {
				if let appIcon {
					Image(nsImage: appIcon)
						.resizable()
						.frame(width: 14, height: 14)
					if let appName = transcript.sourceAppName {
						Text(appName)
							.font(.system(size: 13, weight: .medium))
					}
					Text("\u{00B7}")
						.foregroundStyle(.tertiary)
				}

				Text(transcript.timestamp.relativeFormatted())
				Text("\u{00B7}")
					.foregroundStyle(.tertiary)
				Text(transcript.timestamp.formatted(date: .omitted, time: .shortened))
				Text("\u{00B7}")
					.foregroundStyle(.tertiary)
				Text(String(format: "%.1fs", transcript.duration))

				Spacer()

				// Word count badge
				Text("\(transcript.wordCount) words")
					.font(.system(size: 12))
					.padding(.horizontal, 8)
					.padding(.vertical, 3)
					.background(GlassColors.dropdownBackground)
					.clipShape(RoundedRectangle(cornerRadius: 6))
			}
			.font(.system(size: 13))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 14)
			.padding(.top, 12)
			.padding(.bottom, 8)

			// Transcript text
			Text(transcript.text)
				.font(.body)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 14)
				.padding(.bottom, transcript.llmMetadata != nil ? 4 : 12)

			// LLM post-processing details (collapsible)
			if let meta = transcript.llmMetadata {
				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						showDetails.toggle()
					}
				} label: {
					HStack(spacing: 4) {
						Image(systemName: showDetails ? "chevron.down" : "chevron.right")
							.font(.system(size: 12))
						Text("AI post-processing details")
							.font(.system(size: 13))
					}
					.foregroundStyle(.tertiary)
				}
				.buttonStyle(.plain)
				.padding(.horizontal, 14)
				.padding(.bottom, 4)

				if showDetails {
					VStack(alignment: .leading, spacing: 6) {
						Text("Original:")
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(.tertiary)
						Text(meta.originalText)
							.font(.callout)
							.foregroundStyle(.secondary)
							.lineLimit(nil)
							.fixedSize(horizontal: false, vertical: true)

						HStack(spacing: 0) {
							if let model = meta.model {
								Text(model)
								Text("  \u{00B7}  ").foregroundStyle(.quaternary)
							}
							if let ms = meta.latencyMs {
								Text("\(ms)ms")
								if meta.promptTokens != nil || meta.completionTokens != nil {
									Text("  \u{00B7}  ").foregroundStyle(.quaternary)
								}
							}
							if let pt = meta.promptTokens, let ct = meta.completionTokens {
								Text("\(pt) \u{2192} \(ct) tokens")
							}
						}
						.font(.system(size: 13))
						.foregroundStyle(.tertiary)
					}
					.padding(10)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(GlassColors.dropdownBackground)
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.padding(.horizontal, 14)
					.padding(.bottom, 12)
					.transition(.opacity.combined(with: .move(edge: .top)))
				} else {
					Spacer().frame(height: 8)
				}
			}

			Divider()
				.padding(.horizontal, 14)

			// Action buttons
			HStack(spacing: 12) {
				Spacer()

				Button {
					onCopy()
					showCopyAnimation()
				} label: {
					HStack(spacing: 4) {
						Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
						if showCopied {
							Text("Copied").font(.system(size: 13))
						}
					}
				}
				.buttonStyle(.plain)
				.foregroundStyle(showCopied ? .green : .secondary)
				.help("Copy to clipboard")

				Button(action: onPlay) {
					Image(systemName: isPlaying ? "stop.fill" : "play.fill")
				}
				.buttonStyle(.plain)
				.foregroundStyle(isPlaying ? .blue : .secondary)
				.help(isPlaying ? "Stop playback" : "Play audio")

				Button(action: onDelete) {
					Image(systemName: "trash")
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
				.help("Delete transcript")
			}
			.font(.subheadline)
			.padding(.horizontal, 14)
			.padding(.vertical, 8)
		}
		.background(GlassColors.cardBackground)
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.overlay(
			RoundedRectangle(cornerRadius: 12)
				.strokeBorder(GlassColors.cardBorder, lineWidth: 0.5)
		)
		.shadow(color: .black.opacity(0.10), radius: 8, y: 4)
		.task(id: transcript.sourceAppBundleID) {
			guard let bundleID = transcript.sourceAppBundleID else { return }
			appIcon = await Task.detached(priority: .utility) {
				guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
				else { return nil as NSImage? }
				return NSWorkspace.shared.icon(forFile: url.path)
			}.value
		}
		.task(id: showCopied) {
			guard showCopied else { return }
			try? await Task.sleep(for: .seconds(1.5))
			withAnimation { showCopied = false }
		}
	}

	@State private var showDetails = false
	@State private var showCopied = false

	private func showCopyAnimation() {
		withAnimation {
			showCopied = true
		}
	}
}

// MARK: - Stats View

struct HistoryStatsView: View {
	let history: [Transcript]

	var body: some View {
		HStack(spacing: 12) {
			StatCard(value: "\(history.count)", label: "Transcriptions")
			StatCard(value: "\(totalWords)", label: "Total words")
			StatCard(value: formattedDuration, label: "Audio time")
		}
	}

	private var totalWords: Int {
		history.reduce(0) { $0 + $1.wordCount }
	}

	private var formattedDuration: String {
		let total = history.reduce(0.0) { $0 + $1.duration }
		if total < 60 {
			return String(format: "%.0fs", total)
		} else {
			let minutes = Int(total) / 60
			let seconds = Int(total) % 60
			return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
		}
	}
}

private struct StatCard: View {
	let value: String
	let label: String

	var body: some View {
		VStack(spacing: 4) {
			Text(value)
				.font(.title2.bold())
			Text(label)
				.font(.system(size: 13))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 16)
		.background(GlassColors.cardBackground)
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.overlay(
			RoundedRectangle(cornerRadius: 12)
				.strokeBorder(GlassColors.cardBorder, lineWidth: 0.5)
		)
		.shadow(color: .black.opacity(0.10), radius: 8, y: 4)
	}
}

// MARK: - History View

struct HistoryView: View {
	@ObserveInjection var inject
	let store: StoreOf<HistoryFeature>
	@State private var showingDeleteConfirmation = false
	@Shared(.kolSettings) var kolSettings: KolSettings

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			if !kolSettings.saveTranscriptionHistory {
				SectionHeader(title: "History")
				ContentUnavailableView {
					Label("History Disabled", systemImage: "clock.arrow.circlepath")
				} description: {
					Text("Transcription history is currently disabled.")
				} actions: {
					Button("Enable in Settings") {
						store.send(.navigateToSettings)
					}
				}
			} else if store.transcriptionHistory.history.isEmpty {
				SectionHeader(title: "History")
				ContentUnavailableView {
					Label("No Transcriptions", systemImage: "text.bubble")
				} description: {
					Text("Your transcription history will appear here.")
				}
			} else {
				HStack(alignment: .top) {
					SectionHeader(
						title: "History",
						subtitle: "Your recent transcriptions"
					)

					Spacer()

					Button(role: .destructive) {
						showingDeleteConfirmation = true
					} label: {
						Label("Delete All", systemImage: "trash")
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}

				HistoryStatsView(history: store.transcriptionHistory.history)

				LazyVStack(spacing: 12) {
					ForEach(store.transcriptionHistory.history) { transcript in
						TranscriptView(
							transcript: transcript,
							isPlaying: store.playingTranscriptID == transcript.id,
							onPlay: { store.send(.playTranscript(transcript.id)) },
							onCopy: { store.send(.copyToClipboard(transcript.text)) },
							onDelete: { store.send(.deleteTranscript(transcript.id)) }
						)
					}
				}
			}
		}
		.alert("Delete All Transcripts", isPresented: $showingDeleteConfirmation) {
			Button("Delete All", role: .destructive) {
				store.send(.confirmDeleteAll)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Are you sure you want to delete all transcripts? This action cannot be undone.")
		}
		.enableInjection()
	}
}
