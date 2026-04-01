import Foundation

/// Simple structure representing audio metering values.
public struct Meter: Equatable, Sendable {
  public let averagePower: Double
  public let peakPower: Double

  public init(averagePower: Double, peakPower: Double) {
    self.averagePower = averagePower
    self.peakPower = peakPower
  }
}

/// Broadcasts meter values from a single producer (capture controller / AVAudioRecorder)
/// to multiple consumers. Each call to `subscribe()` returns a fresh AsyncStream.
/// Thread-safe: `yield` can be called from any thread (audio callback, DispatchQueue).
/// `@unchecked Sendable` is safe because all mutable state (`subscribers`) is
/// protected by `NSLock` — every read and write goes through `lock`/`unlock`.
public final class MeterBroadcast: @unchecked Sendable {
  private let lock = NSLock()
  private var subscribers: [UUID: AsyncStream<Meter>.Continuation] = [:]

  public init() {}

  /// Create a new subscriber stream. Call `yield(_:)` to push values to all subscribers.
  public func subscribe() -> AsyncStream<Meter> {
    let id = UUID()
    return AsyncStream<Meter> { continuation in
      self.lock.lock()
      self.subscribers[id] = continuation
      self.lock.unlock()

      continuation.onTermination = { [weak self] _ in
        self?.lock.lock()
        self?.subscribers.removeValue(forKey: id)
        self?.lock.unlock()
      }
    }
  }

  /// Forward a meter value to all current subscribers.
  public func yield(_ meter: Meter) {
    lock.lock()
    let subs = Array(subscribers.values)
    lock.unlock()
    for sub in subs {
      sub.yield(meter)
    }
  }
}
