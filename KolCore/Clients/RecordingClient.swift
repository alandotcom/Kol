import Dependencies
import DependenciesMacros
import Foundation

/// Represents an audio input device
public struct AudioInputDevice: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

@DependencyClient
public struct RecordingClient: Sendable {
  public var startRecording: @Sendable () async -> Void = {}
  public var stopRecording: @Sendable () async -> URL = { URL(fileURLWithPath: "") }
  public var requestMicrophoneAccess: @Sendable () async -> Bool = { false }
  public var observeAudioLevel: @Sendable () async -> AsyncStream<Meter> = { AsyncStream { _ in } }
  public var getAvailableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
  public var getDefaultInputDeviceName: @Sendable () async -> String? = { nil }
  public var warmUpRecorder: @Sendable () async -> Void = {}
  public var cleanup: @Sendable () async -> Void = {}
}

extension RecordingClient: TestDependencyKey {
  public static let testValue = RecordingClient()
}

public extension DependencyValues {
  var recording: RecordingClient {
    get { self[RecordingClient.self] }
    set { self[RecordingClient.self] = newValue }
  }
}
