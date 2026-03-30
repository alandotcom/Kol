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

  /// Smoothed power value — interpolated every frame for fluid amplitude changes.
  @State private var displayPower: Double = 0
  @State private var lastFrameTime: Double = 0

  var body: some View {
    TimelineView(.animation) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate

      // Frame-by-frame exponential smoothing
      let targetPower = min(1.0, (0.7 * averagePower + 0.3 * peakPower) * 1.5)
      let dt = lastFrameTime > 0 ? min(time - lastFrameTime, 0.05) : 0.016
      // Smoothing factor: lower base = snappier response (~60ms to settle)
      let smoothing = pow(0.001, dt)
      let currentPower = displayPower * smoothing + targetPower * (1 - smoothing)
      let effectivePower = max(currentPower, 0.06)

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
      .onChange(of: time) {
        displayPower = currentPower
        lastFrameTime = time
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
