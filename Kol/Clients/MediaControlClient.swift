import AppKit
import AudioToolbox
import CoreAudio
import Dependencies
import DependenciesMacros
import Foundation

private let mediaLogger = KolLog.media

// MARK: - Client Interface

@DependencyClient
struct MediaControlClient {
  /// Pauses media according to the given behavior. Tracks state internally for resumption.
  var pauseForRecording: @Sendable (RecordingAudioBehavior) async -> Void = { _ in }
  /// Resumes whatever was paused by the last `pauseForRecording` call.
  var resumeAfterRecording: @Sendable () async -> Void = {}
}

extension MediaControlClient: DependencyKey {
  static var liveValue: Self {
    let live = MediaControlClientLive()
    return Self(
      pauseForRecording: { await live.pauseForRecording(behavior: $0) },
      resumeAfterRecording: { await live.resumeAfterRecording() }
    )
  }
}

extension DependencyValues {
  var mediaControl: MediaControlClient {
    get { self[MediaControlClient.self] }
    set { self[MediaControlClient.self] = newValue }
  }
}

// MARK: - Live Implementation

private actor MediaControlClientLive {
  private var pausedPlayers: [String] = []
  private var didPauseMedia = false
  private var didPauseViaMediaRemote = false
  private var previousVolume: Float?

  // Backoff to avoid spamming AppleScript errors on systems without controllable players
  private var mediaControlErrorCount = 0
  private var mediaControlDisabled = false

  func pauseForRecording(behavior: RecordingAudioBehavior) async {
    clearState()

    switch behavior {
    case .pauseMedia:
      await pauseMedia()
    case .mute:
      previousVolume = VolumeControl.getSystemVolume()
      VolumeControl.setSystemVolume(0)
      mediaLogger.notice("Muted system volume (was \(String(format: "%.2f", self.previousVolume ?? 0)))")
    case .doNothing:
      break
    }
  }

  func resumeAfterRecording() async {
    if let volume = previousVolume {
      VolumeControl.setSystemVolume(volume)
      mediaLogger.notice("Restored system volume to \(String(format: "%.2f", volume))")
    } else if !self.pausedPlayers.isEmpty {
      mediaLogger.notice("Resuming players: \(self.pausedPlayers.joined(separator: ", "))")
      await Self.resumeMediaApplications(pausedPlayers)
    } else if didPauseViaMediaRemote {
      if mediaRemoteController?.send(.play) == true {
        mediaLogger.notice("Resuming media via MediaRemote")
      } else {
        mediaLogger.error("Failed to resume via MediaRemote; falling back to media key")
        await MainActor.run { Self.sendMediaKey() }
      }
    } else if didPauseMedia {
      await MainActor.run { Self.sendMediaKey() }
      mediaLogger.notice("Resuming media via media key")
    }

    clearState()
  }

  private func clearState() {
    pausedPlayers = []
    didPauseMedia = false
    didPauseViaMediaRemote = false
    previousVolume = nil
  }

  // MARK: - Pause Logic

  private func pauseMedia() async {
    // Try MediaRemote first (most reliable, no AppleScript overhead)
    if let controller = mediaRemoteController {
      let isPlaying = await controller.isMediaPlaying()
      if isPlaying, controller.send(.pause) {
        didPauseViaMediaRemote = true
        mediaLogger.notice("Paused media via MediaRemote")
        return
      }
    }

    // Fall back to AppleScript for specific players
    let paused = await pauseAllMediaApplications()
    pausedPlayers = paused

    // If no specific players were paused, try the generic media key
    if paused.isEmpty {
      if await Self.isAudioPlayingOnDefaultOutput() {
        mediaLogger.notice("Detected active audio on default output; sending media pause")
        await MainActor.run { Self.sendMediaKey() }
        didPauseMedia = true
        mediaLogger.notice("Paused media via media key fallback")
      }
    } else {
      mediaLogger.notice("Paused media players: \(paused.joined(separator: ", "))")
    }
  }

  // MARK: - AppleScript Media Control

  private func pauseAllMediaApplications() async -> [String] {
    if mediaControlDisabled { return [] }
    if Self.installedMediaPlayers.isEmpty { return [] }

    mediaLogger.debug("Installed media players: \(Self.installedMediaPlayers.keys.joined(separator: ", "))")

    var scriptParts: [String] = ["set pausedPlayers to {}"]

    for (appName, _) in Self.installedMediaPlayers {
      if appName == "VLC" {
        scriptParts.append("""
        try
          if application \"VLC\" is running then
            tell application \"VLC\"
              if playing then
                pause
                set end of pausedPlayers to \"VLC\"
              end if
            end tell
          end if
        end try
        """)
      } else {
        scriptParts.append("""
        try
          if application \"\(appName)\" is running then
            tell application \"\(appName)\"
              if player state is playing then
                pause
                set end of pausedPlayers to \"\(appName)\"
              end if
            end tell
          end if
        end try
        """)
      }
    }

    scriptParts.append("return pausedPlayers")
    let script = scriptParts.joined(separator: "\n\n")

    let appleScript = NSAppleScript(source: script)
    var error: NSDictionary?
    guard let resultDescriptor = appleScript?.executeAndReturnError(&error) else {
      if let error = error {
        mediaLogger.error("Failed to pause media apps: \(error)")
        mediaControlErrorCount += 1
        if mediaControlErrorCount >= 3 { mediaControlDisabled = true }
      }
      return []
    }

    var result: [String] = []
    let count = resultDescriptor.numberOfItems
    if count > 0 {
      for i in 1...count {
        if let item = resultDescriptor.atIndex(i)?.stringValue {
          result.append(item)
        }
      }
    }

    return result
  }

  private static func resumeMediaApplications(_ players: [String]) async {
    let validPlayers = players.filter { installedMediaPlayers.keys.contains($0) }
    guard !validPlayers.isEmpty else { return }

    var scriptParts: [String] = []
    for player in validPlayers {
      if player == "VLC" {
        scriptParts.append("""
        try
          if application id \"org.videolan.vlc\" is running then
            tell application id \"org.videolan.vlc\" to play
          end if
        end try
        """)
      } else {
        scriptParts.append("""
        try
          if application \"\(player)\" is running then
            tell application \"\(player)\" to play
          end if
        end try
        """)
      }
    }

    let script = scriptParts.joined(separator: "\n\n")
    let appleScript = NSAppleScript(source: script)
    var error: NSDictionary?
    appleScript?.executeAndReturnError(&error)
    if let error = error {
      mediaLogger.error("Failed to resume media apps: \(error)")
    }
  }

  // MARK: - MediaRemote

  private static func isAudioPlayingOnDefaultOutput() async -> Bool {
    await mediaRemoteController?.isMediaPlaying() ?? false
  }

  /// Simulates a media key press (the Play/Pause key) by posting a system-defined NSEvent.
  @MainActor
  private static func sendMediaKey() {
    let NX_KEYTYPE_PLAY: UInt32 = 16
    func postKeyEvent(down: Bool) {
      let flags: NSEvent.ModifierFlags = down ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
      let data1 = Int((NX_KEYTYPE_PLAY << 16) | (down ? 0xA << 8 : 0xB << 8))
      if let event = NSEvent.otherEvent(with: .systemDefined,
                                        location: .zero,
                                        modifierFlags: flags,
                                        timestamp: 0,
                                        windowNumber: 0,
                                        context: nil,
                                        subtype: 8,
                                        data1: data1,
                                        data2: -1)
      {
        event.cgEvent?.post(tap: .cghidEventTap)
      }
    }
    postKeyEvent(down: true)
    postKeyEvent(down: false)
  }

  // MARK: - Static Helpers

  private static let installedMediaPlayers: [String: String] = {
    var result: [String: String] = [:]
    let workspace = NSWorkspace.shared
    for (name, bundleID) in [
      ("Music", "com.apple.Music"),
      ("iTunes", "com.apple.iTunes"),
      ("Spotify", "com.spotify.client"),
      ("VLC", "org.videolan.vlc"),
    ] {
      if workspace.urlForApplication(withBundleIdentifier: bundleID) != nil {
        result[name] = bundleID
      }
    }
    return result
  }()
}

// MARK: - MediaRemote Controller

/// Function pointer types for the MediaRemote private framework.
private typealias MRNowPlayingIsPlayingFunc = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
private typealias MRMediaRemoteSendCommandFunc = @convention(c) (Int32, CFDictionary?) -> Void

private enum MediaRemoteCommand: Int32 {
  case play = 0
  case pause = 1
  case togglePlayPause = 2
}

/// Wraps a few MediaRemote private framework functions.
private class MediaRemoteController {
  private let mediaRemoteHandle: UnsafeMutableRawPointer
  private let mrNowPlayingIsPlaying: MRNowPlayingIsPlayingFunc
  private var mrSendCommand: MRMediaRemoteSendCommandFunc?

  init?() {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
      mediaLogger.error("Unable to open MediaRemote framework")
      return nil
    }
    mediaRemoteHandle = handle

    guard let playingPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
      mediaLogger.error("Unable to find MRMediaRemoteGetNowPlayingApplicationIsPlaying symbol")
      dlclose(handle)
      return nil
    }
    mrNowPlayingIsPlaying = unsafeBitCast(playingPtr, to: MRNowPlayingIsPlayingFunc.self)

    if let commandPtr = dlsym(handle, "MRMediaRemoteSendCommand") {
      mrSendCommand = unsafeBitCast(commandPtr, to: MRMediaRemoteSendCommandFunc.self)
    } else {
      mediaLogger.error("Unable to find MRMediaRemoteSendCommand symbol")
    }
  }

  deinit {
    dlclose(mediaRemoteHandle)
  }

  func isMediaPlaying() async -> Bool {
    await withCheckedContinuation { continuation in
      mrNowPlayingIsPlaying(DispatchQueue.main) { isPlaying in
        continuation.resume(returning: isPlaying)
      }
    }
  }

  func send(_ command: MediaRemoteCommand) -> Bool {
    guard let sendCommand = mrSendCommand else { return false }
    sendCommand(command.rawValue, nil)
    return true
  }
}

/// Global instance — initialized once, reused for all media queries.
private let mediaRemoteController = MediaRemoteController()

// MARK: - Volume Control

enum VolumeControl {
  static func getSystemVolume() -> Float {
    guard let deviceID = defaultOutputDevice() else { return 0.0 }
    var volume: Float32 = 0.0
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = audioPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)

    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    if status != 0 {
      mediaLogger.error("Failed to get system volume: \(status)")
      return 0.0
    }
    return volume
  }

  static func setSystemVolume(_ volume: Float) {
    guard let deviceID = defaultOutputDevice() else { return }
    var newVolume = volume
    let size = UInt32(MemoryLayout<Float32>.size)
    var address = audioPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)

    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &newVolume)
    if status != 0 {
      mediaLogger.error("Failed to set system volume: \(status)")
    }
  }

  private static func defaultOutputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    if status != 0 {
      mediaLogger.error("Failed to get default output device: \(status)")
      return nil
    }
    return deviceID
  }
}
