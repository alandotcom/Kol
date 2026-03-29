//
//  TranscriptionIndicatorView.swift
//  Hex
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
    case prewarming
    case completed
  }

  var status: Status
  var meter: Meter

  private let panelWidth: CGFloat = 380
  private let panelHeight: CGFloat = 130
  private let panelCornerRadius: CGFloat = 20

  @State private var transcribeEffect = 0

  var body: some View {
    let averagePower = min(1, meter.averagePower * 3)
    let peakPower = min(1, meter.peakPower * 3)

    ZStack {
      // Frosted glass panel
      RoundedRectangle(cornerRadius: panelCornerRadius)
        .fill(.ultraThinMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: panelCornerRadius)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

      // Content per state
      Group {
        switch status {
        case .recording:
          AudioWaveformView(
            averagePower: averagePower,
            peakPower: peakPower
          )
          .padding(.horizontal, 24)

        case .transcribing, .prewarming, .completed:
          EmptyView()

        case .optionKeyPressed:
          Circle()
            .fill(Color.primary.opacity(0.3))
            .frame(width: 8, height: 8)

        case .hidden:
          EmptyView()
        }
      }
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: meter)
    }
    .frame(width: panelWidth, height: panelHeight)
    .opacity(status == .recording || status == .optionKeyPressed ? 1 : 0)
    .scaleEffect(status == .recording || status == .optionKeyPressed ? 1 : 0.85)
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status)
    .enableInjection()
  }
}

#Preview("Indicator States") {
  VStack(spacing: 20) {
    TranscriptionIndicatorView(status: .optionKeyPressed, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .recording, meter: .init(averagePower: 0.4, peakPower: 0.5))
    TranscriptionIndicatorView(status: .transcribing, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .completed, meter: .init(averagePower: 0, peakPower: 0))
  }
  .padding(40)
}
