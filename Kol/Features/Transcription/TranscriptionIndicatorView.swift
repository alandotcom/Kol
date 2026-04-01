//
//  TranscriptionIndicatorView.swift
//  Kol
//
//  Originally by Kit Langton on 1/25/25.
//  Redesigned: frosted glass panel with Super Whisper-style waveform.

import Inject
import Pow
import SwiftUI

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject

  enum Status: Equatable {
    case hidden
    case optionKeyPressed
    case recording
    case transcribing
    case postProcessing
    case prewarming
    case completed
  }

  var status: Status
  var meter: Meter

  private let panelWidth: CGFloat = 190
  private let panelHeight: CGFloat = 35
  private let panelCornerRadius: CGFloat = 10

  var body: some View {
    // During recording, pass real meter values. During processing,
    // the waveform naturally decays to a flat line via the smoother.
    let isActive = status == .recording
    let averagePower = isActive ? min(1, max(0, meter.averagePower - 0.003) * 50) : 0.0
    let peakPower = isActive ? min(1, max(0, meter.peakPower - 0.003) * 50) : 0.0

    ZStack {
      // Dark panel with macOS-style depth
      RoundedRectangle(cornerRadius: panelCornerRadius)
        .fill(Color.black.opacity(0.75))
        .overlay {
          RoundedRectangle(cornerRadius: panelCornerRadius)
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
        .overlay {
          // Top highlight — simulates light catching the top edge
          RoundedRectangle(cornerRadius: panelCornerRadius)
            .stroke(
              LinearGradient(
                colors: [.white.opacity(0.25), .clear, .clear],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: 0.5
            )
            .padding(0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

      // Waveform stays visible during recording AND processing —
      // it just smoothly decays to a flat line when power drops to 0.
      AudioWaveformView(
        averagePower: averagePower,
        peakPower: peakPower
      )
      .padding(.horizontal, 12)
      .opacity(status == .recording || isProcessing ? 1 : 0)

      // Option key dot
      Circle()
        .fill(Color.white.opacity(0.3))
        .frame(width: 6, height: 6)
        .opacity(status == .optionKeyPressed ? 1 : 0)
    }
    .frame(width: panelWidth, height: panelHeight)
    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
    .opacity(panelVisible ? 1 : 0)
    .scaleEffect(panelVisible ? 1 : 0.85)
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityStatusLabel)
    .enableInjection()
  }

  private var isProcessing: Bool {
    status == .transcribing || status == .postProcessing
  }

  /// Panel stays visible from optionKeyPressed/recording through transcribing/postProcessing.
  /// Only hides on .hidden and .completed (completed uses the showCompleted overlay in TranscriptionView).
  private var panelVisible: Bool {
    switch status {
    case .optionKeyPressed, .recording, .transcribing, .postProcessing, .prewarming: true
    case .hidden, .completed: false
    }
  }

  private var accessibilityStatusLabel: String {
    switch status {
    case .recording: "Recording"
    case .transcribing: "Transcribing"
    case .postProcessing: "Processing text"
    case .prewarming: "Preparing"
    case .completed: "Transcription complete"
    case .optionKeyPressed: "Ready to record"
    case .hidden: ""
    }
  }

}

#Preview("Indicator States") {
  VStack(spacing: 20) {
    TranscriptionIndicatorView(status: .optionKeyPressed, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .recording, meter: .init(averagePower: 0.4, peakPower: 0.5))
    TranscriptionIndicatorView(status: .transcribing, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .postProcessing, meter: .init(averagePower: 0, peakPower: 0))
  }
  .padding(40)
}
