import AVFoundation

// TODO: Extract into a PlaybackClient dependency for full @MainActor isolation
// and testability. Currently stored directly in HistoryFeature.State which
// prevents @MainActor annotation (State mutating methods aren't actor-isolated).
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

	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
		self.player = nil
		let callback = onPlaybackFinished
		onPlaybackFinished = nil
		Task { @MainActor in
			callback?()
		}
	}
}
