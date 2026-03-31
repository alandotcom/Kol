import Foundation

/// Frame-to-frame smoothing for audio waveform amplitude.
///
/// Behavioral contracts:
/// - **Attack**: louder values snap instantly (zero delay) for responsive feel.
/// - **Decay**: quieter values decay smoothly via exponential falloff.
/// - **Floor**: output never drops below 0.06 so the waveform stays visible.
/// - **First frame**: initializes to current target (no jump from zero).
/// - **dt clamping**: large time gaps (background/resume) are capped at 0.05s.
public final class WaveformSmoother {
  public var displayPower: Double = 0
  public var lastFrameTime: Double = 0

  public init() {}

  /// Compute smoothed power for this frame and update internal state. Returns effective power for rendering.
  public func update(time: Double, averagePower: Double, peakPower: Double) -> Double {
    let targetPower = min(1.0, (0.7 * averagePower + 0.3 * peakPower) * 1.5)

    if lastFrameTime == 0 {
      displayPower = targetPower
      lastFrameTime = time
      return max(displayPower, 0.06)
    }

    let dt = min(time - lastFrameTime, 0.05)
    if targetPower > displayPower {
      // Attack: instant snap to louder values (zero delay)
      displayPower = targetPower
    } else {
      // Decay: smooth falloff for natural feel
      let smoothing = pow(0.001, dt)
      displayPower = displayPower * smoothing + targetPower * (1 - smoothing)
    }
    lastFrameTime = time
    return max(displayPower, 0.06)
  }
}
