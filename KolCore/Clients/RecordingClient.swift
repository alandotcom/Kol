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
  public var startRecording: @Sendable (_ sessionID: UUID) async -> RecordingStartOutcome = { _ in .superseded }
  public var stopRecording: @Sendable (_ sessionID: UUID) async -> RecordingStopOutcome = { _ in .stale }
  public var discardRecording: @Sendable (_ sessionID: UUID) async -> Void = { _ in }
  public var requestMicrophoneAccess: @Sendable () async -> Bool = { false }
  public var observeAudioLevel: @Sendable () async -> AsyncStream<Meter> = { AsyncStream { _ in } }
  public var getAvailableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
  public var getDefaultInputDeviceName: @Sendable () async -> String? = { nil }
  public var warmUpRecorder: @Sendable () async -> Void = {}
  public var cleanup: @Sendable () async -> Void = {}
}

public enum RecordingFailure: Error, Equatable, Sendable, LocalizedError {
  case unavailable
  case missingAudio
  case backend(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable: "The microphone could not start recording."
    case .missingAudio: "The recording did not produce an audio file."
    case let .backend(message): message
    }
  }
}

public enum RecordingStartOutcome: Equatable, Sendable {
  case started
  case superseded
  case failed(RecordingFailure)
}

public enum RecordingStopOutcome: Equatable, Sendable {
  case audio(URL)
  case stale
  case failed(RecordingFailure)
}

/// Actor-confined admission for the single microphone take.
public struct RecordingTakeSlot: Sendable {
  public private(set) var activeID: UUID?
  private var retiredIDs: Set<UUID> = []

  public init() {}

  public func canAdmit(_ id: UUID, cancelled: Bool) -> Bool {
    !cancelled && activeID != id && !retiredIDs.contains(id)
  }

  public mutating func admit(_ id: UUID, cancelled: Bool) -> Bool {
    guard canAdmit(id, cancelled: cancelled) else { return false }
    if let activeID { retiredIDs.insert(activeID) }
    activeID = id
    return true
  }

  public func owns(_ id: UUID) -> Bool { activeID == id }

  @discardableResult
  public mutating func finish(_ id: UUID) -> Bool {
    guard owns(id) else { return false }
    retiredIDs.insert(id)
    activeID = nil
    return true
  }
}

public struct RecordingMediaTaskChain: Sendable {
  private var task: Task<Void, Never>?

  public init() {}

  public mutating func enqueue(_ operation: @escaping @Sendable () async -> Void) {
    let previous = task
    task = Task {
      await previous?.value
      await operation()
    }
  }

  public func finish() async { await task?.value }
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
