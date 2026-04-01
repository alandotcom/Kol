import Dependencies
import DependenciesMacros
import Foundation

public struct KeyEventMonitorToken: Sendable {
  private let cancelHandler: @Sendable () -> Void

  public init(cancel: @escaping @Sendable () -> Void) {
    self.cancelHandler = cancel
  }

  public func cancel() {
    cancelHandler()
  }

  public static let noop = KeyEventMonitorToken(cancel: {})
}

@DependencyClient
public struct KeyEventMonitorClient: Sendable {
  public var listenForKeyPress: @Sendable () async -> AsyncThrowingStream<KeyEvent, Error> = { .never }
  public var handleKeyEvent: @Sendable (@Sendable @escaping (KeyEvent) -> Bool) -> KeyEventMonitorToken = { _ in .noop }
  public var handleInputEvent: @Sendable (@Sendable @escaping (InputEvent) -> Bool) -> KeyEventMonitorToken = { _ in .noop }
  public var startMonitoring: @Sendable () async -> Void = {}
  public var stopMonitoring: @Sendable () -> Void = {}
}

extension KeyEventMonitorClient: TestDependencyKey {
  public static let testValue = KeyEventMonitorClient()
}

public extension DependencyValues {
  var keyEventMonitor: KeyEventMonitorClient {
    get { self[KeyEventMonitorClient.self] }
    set { self[KeyEventMonitorClient.self] = newValue }
  }
}
