import AVFoundation
import ComposableArchitecture
import Dependencies

private let historyLogger = KolLog.history

// MARK: - History Feature

@Reducer
struct HistoryFeature {
	@ObservableState
	struct State: Equatable {
		@Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
		var playingTranscriptID: UUID?
		var playbackSessionID: UUID?
		var playbackError: String?
		var audioPlayer: AVAudioPlayer?
		var audioPlayerController: AudioPlayerController?

		mutating func stopAudioPlayback() {
			audioPlayerController?.stop()
			audioPlayer = nil
			audioPlayerController = nil
			playingTranscriptID = nil
			playbackSessionID = nil
		}
	}

	enum Action {
		case playTranscript(UUID)
		case stopPlayback
		case copyToClipboard(String)
		case deleteTranscript(UUID)
		case deleteAllTranscripts
		case confirmDeleteAll
		case playbackFinished(UUID)
		case dismissPlaybackError
		case navigateToSettings
	}

	private enum CancelID { case playback }

	@Dependency(\.pasteboard) var pasteboard
	@Dependency(\.transcriptPersistence) var transcriptPersistence

	private func deleteAudioEffect(for transcripts: [Transcript]) -> Effect<Action> {
		.run { [transcriptPersistence] _ in
			await transcriptPersistence.deleteAudioFiles(for: transcripts)
		}
	}

	var body: some ReducerOf<Self> {
		Reduce { state, action in
			switch action {
			case let .playTranscript(id):
				state.playbackError = nil
				if state.playingTranscriptID == id {
					state.stopAudioPlayback()
					return .cancel(id: CancelID.playback)
				}

				state.stopAudioPlayback()

				guard let transcript = state.transcriptionHistory.history.first(where: { $0.id == id }) else {
					return .cancel(id: CancelID.playback)
				}

				do {
					let controller = AudioPlayerController()
					let sessionID = UUID()
					let completion = AsyncStream<Void> { continuation in
						controller.onPlaybackFinished = {
							continuation.yield(())
							continuation.finish()
						}
					}
					let player = try controller.play(url: transcript.audioPath)

					state.audioPlayer = player
					state.audioPlayerController = controller
					state.playingTranscriptID = id
					state.playbackSessionID = sessionID

					return .run { send in
						for await _ in completion {
							guard !Task.isCancelled else { return }
							await send(.playbackFinished(sessionID))
						}
					}
					.cancellable(id: CancelID.playback, cancelInFlight: true)
				} catch {
					historyLogger.error("Failed to play audio: \(error.localizedDescription)")
					state.playbackError = "The recording is missing or could not be opened. You can still read and copy its transcript."
					return .cancel(id: CancelID.playback)
				}

			case .stopPlayback:
				state.stopAudioPlayback()
				return .cancel(id: CancelID.playback)

			case let .playbackFinished(sessionID):
				guard state.playbackSessionID == sessionID else { return .none }
				state.stopAudioPlayback()
				return .none

			case let .copyToClipboard(text):
				return .run { [pasteboard] _ in
					await pasteboard.copy(text)
				}

			case let .deleteTranscript(id):
				guard let transcript = state.transcriptionHistory.history.first(where: { $0.id == id }) else {
					return .none
				}

				let wasPlaying = state.playingTranscriptID == id

				if state.playingTranscriptID == id {
					state.stopAudioPlayback()
				}

				state.$transcriptionHistory.withLock { history in
					history.history.removeAll { $0.id == id }
				}

				return .merge(
					deleteAudioEffect(for: [transcript]),
					wasPlaying ? .cancel(id: CancelID.playback) : .none
				)

			case .deleteAllTranscripts:
				return .send(.confirmDeleteAll)

			case .confirmDeleteAll:
				let transcripts = state.transcriptionHistory.history
				state.stopAudioPlayback()

				state.$transcriptionHistory.withLock { history in
					history.history.removeAll()
				}

				return .merge(deleteAudioEffect(for: transcripts), .cancel(id: CancelID.playback))

			case .dismissPlaybackError:
				state.playbackError = nil
				return .none

			case .navigateToSettings:
				return .none
			}
		}
	}
}
