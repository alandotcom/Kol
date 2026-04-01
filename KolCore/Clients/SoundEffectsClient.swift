import Dependencies
import DependenciesMacros
import Foundation

public enum SoundEffect: String, CaseIterable, Sendable {
  case pasteTranscript
  case startRecording
  case stopRecording
  case cancel

  /// Returns the audio file name for the given theme, falling back to the default name
  /// if a themed variant doesn't exist in the bundle.
  public func fileName(for theme: SoundTheme) -> String {
    guard theme != .standard else { return rawValue }
    let themed = "\(rawValue)_\(theme.rawValue)"
    if Bundle.main.url(forResource: themed, withExtension: "mp3") != nil {
      return themed
    }
    return rawValue
  }

  public var fileExtension: String {
    "mp3"
  }
}

@DependencyClient
public struct SoundEffectsClient: Sendable {
  public var play: @Sendable (SoundEffect) -> Void
  public var stop: @Sendable (SoundEffect) -> Void
  public var stopAll: @Sendable () -> Void
  public var preloadSounds: @Sendable () async -> Void
  public var reloadSounds: @Sendable () -> Void
}

extension SoundEffectsClient: TestDependencyKey {
  public static let testValue = SoundEffectsClient(
    play: { _ in },
    stop: { _ in },
    stopAll: {},
    preloadSounds: {},
    reloadSounds: {}
  )
}

public extension DependencyValues {
  var soundEffects: SoundEffectsClient {
    get { self[SoundEffectsClient.self] }
    set { self[SoundEffectsClient.self] = newValue }
  }
}
