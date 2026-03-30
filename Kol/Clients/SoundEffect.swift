//
//  SoundEffect.swift
//  Kol
//
//  Created by Kit Langton on 1/26/25.
//

import AVFoundation
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import SwiftUI

public enum SoundEffect: String, CaseIterable {
  case pasteTranscript
  case startRecording
  case stopRecording
  case cancel

  /// Returns the audio file name for the given theme, falling back to the default name
  /// if a themed variant doesn't exist in the bundle.
  func fileName(for theme: SoundTheme) -> String {
    guard theme != .standard else { return rawValue }
    let themed = "\(rawValue)_\(theme.rawValue)"
    if Bundle.main.url(forResource: themed, withExtension: "mp3") != nil {
      return themed
    }
    return rawValue
  }

  var fileExtension: String {
    "mp3"
  }
}

@DependencyClient
public struct SoundEffectsClient {
  public var play: @Sendable (SoundEffect) -> Void
  public var stop: @Sendable (SoundEffect) -> Void
  public var stopAll: @Sendable () -> Void
  public var preloadSounds: @Sendable () async -> Void
  public var reloadSounds: @Sendable () -> Void
}

extension SoundEffectsClient: DependencyKey {
  public static var liveValue: SoundEffectsClient {
    let live = SoundEffectsClientLive()
    return SoundEffectsClient(
      play: { soundEffect in
        Task { await live.play(soundEffect) }
      },
      stop: { soundEffect in
        Task { await live.stop(soundEffect) }
      },
      stopAll: {
        Task { await live.stopAll() }
      },
      preloadSounds: {
        await live.preloadSounds()
      },
      reloadSounds: {
        Task { await live.reloadSounds() }
      }
    )
  }
}

public extension DependencyValues {
  var soundEffects: SoundEffectsClient {
    get { self[SoundEffectsClient.self] }
    set { self[SoundEffectsClient.self] = newValue }
  }
}

actor SoundEffectsClientLive {
  private let logger = KolLog.sound
  private let baselineVolume = KolSettings.baseSoundEffectsVolume

  private let engine = AVAudioEngine()
  @Shared(.kolSettings) var kolSettings: KolSettings
  private var playerNodes: [SoundEffect: AVAudioPlayerNode] = [:]
  private var audioBuffers: [SoundEffect: AVAudioPCMBuffer] = [:]
  private var isEngineRunning = false

  func play(_ soundEffect: SoundEffect) {
	guard kolSettings.soundEffectsEnabled else { return }
	guard let player = playerNodes[soundEffect], let buffer = audioBuffers[soundEffect] else {
		logger.error("Requested sound \(soundEffect.rawValue) not preloaded")
		return
	}
	prepareEngineIfNeeded()
	let clampedVolume = min(max(kolSettings.soundEffectsVolume, 0), baselineVolume)
	player.volume = Float(clampedVolume)
	player.stop()
	player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
	player.play()
  }

  func stop(_ soundEffect: SoundEffect) {
    playerNodes[soundEffect]?.stop()
  }

  func stopAll() {
    playerNodes.values.forEach { $0.stop() }
  }

  func preloadSounds() async {
    guard !isSetup else { return }
    let theme = kolSettings.soundTheme
    for soundEffect in SoundEffect.allCases {
      loadSound(soundEffect, theme: theme)
    }
    prepareEngineIfNeeded()
    isSetup = true
  }

  func reloadSounds() {
    // Stop and detach existing players
    for (_, player) in playerNodes {
      player.stop()
      engine.detach(player)
    }
    playerNodes.removeAll()
    audioBuffers.removeAll()

    let theme = kolSettings.soundTheme
    for soundEffect in SoundEffect.allCases {
      loadSound(soundEffect, theme: theme)
    }
    prepareEngineIfNeeded()
  }

  private var isSetup = false

  private func loadSound(_ soundEffect: SoundEffect, theme: SoundTheme) {
    let fileName = soundEffect.fileName(for: theme)
    guard let url = Bundle.main.url(
      forResource: fileName,
      withExtension: soundEffect.fileExtension
    ) else {
      logger.error("Missing sound resource \(fileName).\(soundEffect.fileExtension)")
      return
    }

    do {
      let file = try AVAudioFile(forReading: url)
      let frameCount = AVAudioFrameCount(file.length)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
        logger.error("Failed to allocate buffer for \(soundEffect.rawValue)")
        return
      }
      try file.read(into: buffer)
      audioBuffers[soundEffect] = buffer

      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
      playerNodes[soundEffect] = player
    } catch {
      logger.error("Failed to load sound \(soundEffect.rawValue): \(error.localizedDescription)")
    }
  }

  private func prepareEngineIfNeeded() {
    if !isEngineRunning || !engine.isRunning {
      engine.prepare()
      if #available(macOS 13.0, *) {
        engine.isAutoShutdownEnabled = false
      }
      do {
        try engine.start()
        isEngineRunning = true
      } catch {
        logger.error("Failed to start AVAudioEngine: \(error.localizedDescription)")
      }
    }
  }
}
