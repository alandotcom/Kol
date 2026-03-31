//
//  AudioWaveformView.swift
//  Kol
//
//  Continuous sine waveform: multiple overlapping sine waves summed together
//  into smooth flowing lines. Amplitude responds to microphone input with
//  frame-by-frame exponential smoothing for perfectly fluid motion.

import Inject
import SwiftUI

struct AudioWaveformView: View {
  @ObserveInjection var inject

  var averagePower: Double
  var peakPower: Double

  /// Reference-type smoother — mutated directly in the TimelineView body each frame.
  /// Avoids @State inside TimelineView, which is unreliable on macOS 26.
  @State private var smoother = WaveformSmoother()

  /// Drive at display refresh rate only while audio is flowing; drop to idle otherwise.
  private var isActive: Bool { averagePower > 0 || peakPower > 0 }

  var body: some View {
    TimelineView(isActive ? .animation : .animation(paused: true)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      let effectivePower = smoother.update(time: time, averagePower: averagePower, peakPower: peakPower)

      Canvas { context, size in
        let midY = size.height / 2
        let amplitude = midY * 0.85 * effectivePower

        // Top wave (above center)
        let topPath = waveformPath(
          width: size.width, midY: midY, amplitude: amplitude,
          time: time, sign: -1
        )
        context.stroke(topPath, with: .color(.primary.opacity(0.55)), lineWidth: 2)

        // Bottom wave (mirrored below center)
        let bottomPath = waveformPath(
          width: size.width, midY: midY, amplitude: amplitude,
          time: time, sign: 1
        )
        context.stroke(bottomPath, with: .color(.primary.opacity(0.55)), lineWidth: 2)
      }
    }
    .enableInjection()
  }

  private func waveformPath(
    width: CGFloat, midY: CGFloat, amplitude: CGFloat,
    time: Double, sign: CGFloat
  ) -> Path {
    let steps = 240

    var points = [CGPoint]()
    points.reserveCapacity(steps + 1)

    for i in 0...steps {
      let normalizedX = Double(i) / Double(steps)
      let x = width * CGFloat(normalizedX)

      // Envelope: taper at edges
      let envelope = pow(sin(normalizedX * .pi), 0.5)

      // Sum of multiple sine waves at different frequencies/speeds
      let wave1 = sin(normalizedX * 4.0 * .pi + time * 8.0)
      let wave2 = sin(normalizedX * 6.5 * .pi - time * 6.0) * 0.6
      let wave3 = sin(normalizedX * 9.0 * .pi + time * 10.0) * 0.3
      let combined = (wave1 + wave2 + wave3) / 1.9

      let y = midY + sign * amplitude * envelope * CGFloat(abs(combined))
      points.append(CGPoint(x: x, y: y))
    }

    var path = Path()
    guard points.count > 1 else { return path }
    path.move(to: points[0])

    // Catmull-Rom spline for silky smooth curves
    for i in 0..<points.count - 1 {
      let p0 = points[max(i - 1, 0)]
      let p1 = points[i]
      let p2 = points[min(i + 1, points.count - 1)]
      let p3 = points[min(i + 2, points.count - 1)]

      let cp1 = CGPoint(
        x: p1.x + (p2.x - p0.x) / 6,
        y: p1.y + (p2.y - p0.y) / 6
      )
      let cp2 = CGPoint(
        x: p2.x - (p3.x - p1.x) / 6,
        y: p2.y - (p3.y - p1.y) / 6
      )
      path.addCurve(to: p2, control1: cp1, control2: cp2)
    }

    return path
  }
}

#Preview("Waveform") {
  VStack(spacing: 30) {
    Text("Silent").font(.caption)
    AudioWaveformView(averagePower: 0, peakPower: 0)
      .frame(height: 100)

    Text("Medium").font(.caption)
    AudioWaveformView(averagePower: 0.4, peakPower: 0.5)
      .frame(height: 100)

    Text("Loud").font(.caption)
    AudioWaveformView(averagePower: 0.9, peakPower: 1.0)
      .frame(height: 100)
  }
  .padding(40)
  .background(.background)
}
