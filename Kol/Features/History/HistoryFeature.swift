import AVFoundation
import AppKit
import ComposableArchitecture
import Dependencies
import KolCore
import Inject
import SwiftUI

private let historyLogger = KolLog.history

// MARK: - Date Extensions

extension Date {
	func relativeFormatted() -> String {
		let calendar = Calendar.current
		let now = Date()

		if calendar.isDateInToday(self) {
			return "Today"
		} else if calendar.isDateInYesterday(self) {
			return "Yesterday"
		} else if let daysAgo = calendar.dateComponents([.day], from: self, to: now).day, daysAgo < 7 {
			let formatter = DateFormatter()
			formatter.dateFormat = "EEEE" // Day of week
			return formatter.string(from: self)
		} else {
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			return formatter.string(from: self)
		}
	}
}

// MARK: - Models

extension SharedReaderKey
	where Self == FileStorageKey<TranscriptionHistory>.Default
{
	static var transcriptionHistory: Self {
		Self[
			.fileStorage(.transcriptionHistoryURL),
			default: .init()
		]
	}
}

// MARK: - Storage Migration

extension URL {
	static var transcriptionHistoryURL: URL {
		get {
			URL.kolMigratedFileURL(named: "transcription_history.json")
		}
	}
}

class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
	private var player: AVAudioPlayer?
	var onPlaybackFinished: (() -> Void)?

	func play(url: URL) throws -> AVAudioPlayer {
		let player = try AVAudioPlayer(contentsOf: url)
		player.delegate = self
		player.play()
		self.player = player
		return player
	}

	func stop() {
		player?.stop()
		player = nil
		// AVAudioPlayer.stop() does NOT call audioPlayerDidFinishPlaying,
		// so we must fire the callback manually to resume any waiting continuation.
		let callback = onPlaybackFinished
		onPlaybackFinished = nil
		callback?()
	}

	// AVAudioPlayerDelegate method
	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
		self.player = nil
		let callback = onPlaybackFinished
		onPlaybackFinished = nil
		Task { @MainActor in
			callback?()
		}
	}
}

// MARK: - History Feature

@Reducer
struct HistoryFeature {
	@ObservableState
	struct State: Equatable {
		@Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
		var playingTranscriptID: UUID?
		var audioPlayer: AVAudioPlayer?
		var audioPlayerController: AudioPlayerController?

		mutating func stopAudioPlayback() {
			audioPlayerController?.stop()
			audioPlayer = nil
			audioPlayerController = nil
			playingTranscriptID = nil
		}
	}

	enum Action {
		case playTranscript(UUID)
		case stopPlayback
		case copyToClipboard(String)
		case deleteTranscript(UUID)
		case deleteAllTranscripts
		case confirmDeleteAll
		case playbackFinished
		case navigateToSettings
	}

	@Dependency(\.pasteboard) var pasteboard
	@Dependency(\.transcriptPersistence) var transcriptPersistence

	private func deleteAudioEffect(for transcripts: [Transcript]) -> Effect<Action> {
		.run { [transcriptPersistence] _ in
			for transcript in transcripts {
				try? await transcriptPersistence.deleteAudio(transcript)
			}
		}
	}

	var body: some ReducerOf<Self> {
		Reduce { state, action in
			switch action {
			case let .playTranscript(id):
				if state.playingTranscriptID == id {
					state.stopAudioPlayback()
					return .none
				}

				state.stopAudioPlayback()

				guard let transcript = state.transcriptionHistory.history.first(where: { $0.id == id }) else {
					return .none
				}

				do {
					let controller = AudioPlayerController()
					let player = try controller.play(url: transcript.audioPath)

					state.audioPlayer = player
					state.audioPlayerController = controller
					state.playingTranscriptID = id

					return .run { send in
						await withCheckedContinuation { continuation in
							controller.onPlaybackFinished = {
								continuation.resume()
								Task { @MainActor in
									send(.playbackFinished)
								}
							}
						}
					}
				} catch {
					historyLogger.error("Failed to play audio: \(error.localizedDescription)")
					return .none
				}

			case .stopPlayback, .playbackFinished:
				state.stopAudioPlayback()
				return .none

			case let .copyToClipboard(text):
				return .run { [pasteboard] _ in
					await pasteboard.copy(text)
				}

			case let .deleteTranscript(id):
				guard let index = state.transcriptionHistory.history.firstIndex(where: { $0.id == id }) else {
					return .none
				}

				let transcript = state.transcriptionHistory.history[index]

				if state.playingTranscriptID == id {
					state.stopAudioPlayback()
				}

				_ = state.$transcriptionHistory.withLock { history in
					history.history.remove(at: index)
				}

				return deleteAudioEffect(for: [transcript])

			case .deleteAllTranscripts:
				return .send(.confirmDeleteAll)

			case .confirmDeleteAll:
				let transcripts = state.transcriptionHistory.history
				state.stopAudioPlayback()

				state.$transcriptionHistory.withLock { history in
					history.history.removeAll()
				}

				return deleteAudioEffect(for: transcripts)

			case .navigateToSettings:
				return .none
			}
		}
	}
}

// MARK: - Transcript Card View

struct TranscriptView: View {
	let transcript: Transcript
	let isPlaying: Bool
	let onPlay: () -> Void
	let onCopy: () -> Void
	let onDelete: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Metadata bar
			HStack(spacing: 6) {
				if let bundleID = transcript.sourceAppBundleID,
				   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
					Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
						.resizable()
						.frame(width: 14, height: 14)
					if let appName = transcript.sourceAppName {
						Text(appName)
							.font(.caption.weight(.medium))
					}
					Text("·")
						.foregroundStyle(.tertiary)
				}

				Text(transcript.timestamp.relativeFormatted())
				Text("·")
					.foregroundStyle(.tertiary)
				Text(transcript.timestamp.formatted(date: .omitted, time: .shortened))
				Text("·")
					.foregroundStyle(.tertiary)
				Text(String(format: "%.1fs", transcript.duration))

				Spacer()

				// Word count badge
				let wordCount = transcript.text.split(separator: " ").count
				Text("\(wordCount) words")
					.font(.caption2)
					.padding(.horizontal, 8)
					.padding(.vertical, 3)
					.background(GlassColors.dropdownBackground)
					.clipShape(RoundedRectangle(cornerRadius: 6))
			}
			.font(.caption)
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
				.padding(.bottom, 12)

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
							Text("Copied").font(.caption)
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
		.shadow(color: .black.opacity(0.08), radius: 4, y: 2)
		.shadow(color: .black.opacity(0.08), radius: 12, y: 8)
		.onDisappear {
			copyTask?.cancel()
		}
	}

	@State private var showCopied = false
	@State private var copyTask: Task<Void, Error>?

	private func showCopyAnimation() {
		copyTask?.cancel()

		copyTask = Task {
			withAnimation {
				showCopied = true
			}

			try await Task.sleep(for: .seconds(1.5))

			withAnimation {
				showCopied = false
			}
		}
	}
}

// MARK: - Stats View

private struct HistoryStatsView: View {
	let history: [Transcript]

	var body: some View {
		HStack(spacing: 12) {
			StatCard(value: "\(history.count)", label: "Transcriptions")
			StatCard(value: "\(totalWords)", label: "Total words")
			StatCard(value: formattedDuration, label: "Audio time")
		}
	}

	private var totalWords: Int {
		history.reduce(0) { $0 + $1.text.split(separator: " ").count }
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
				.font(.caption)
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
		.shadow(color: .black.opacity(0.08), radius: 4, y: 2)
		.shadow(color: .black.opacity(0.08), radius: 12, y: 8)
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
