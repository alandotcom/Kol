import Inject
import SwiftUI

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  enum Status: Equatable {
    case hidden, optionKeyPressed, recording, transcribing, postProcessing, prewarming

    var label: String {
      switch self {
      case .hidden: ""
      case .optionKeyPressed: "Ready"
      case .recording: "Recording"
      case .transcribing: "Transcribing"
      case .postProcessing: "Cleaning up"
      case .prewarming: "Preparing"
      }
    }

    var isProcessing: Bool {
      self == .transcribing || self == .postProcessing || self == .prewarming
    }
  }

  var status: Status
  var meter: Meter
  var forceReduceMotion = false
  var forceReduceTransparency = false

  var body: some View {
    HStack(spacing: 12) {
      if status.isProcessing {
        ProgressView()
          .controlSize(.small)
          .frame(width: 18, height: 18)
          .accessibilityHidden(true)
      } else {
        Image(systemName: status == .recording ? "mic.fill" : "mic")
          .foregroundStyle(status == .recording ? Color.accentColor : Color.secondary)
          .frame(width: 18, height: 18)
          .accessibilityHidden(true)
      }
      Text(status.label)
        .font(.callout.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
      if status == .recording {
        RecordingLevelView(meter: meter, reduceMotion: reduceMotion || forceReduceMotion)
          .frame(width: 48, height: 22)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16)
    .frame(width: 248, height: 52)
    .background {
      if reduceTransparency || forceReduceTransparency {
        RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor))
      } else {
        RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
      }
    }
    .opacity(status == .hidden ? 0 : 1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Kol")
    .accessibilityValue(status.label)
    .accessibilityHidden(status == .hidden)
    .enableInjection()
  }
}

/// Meter bars reflect microphone input without a perpetual decorative animation.
private struct RecordingLevelView: View {
  var meter: Meter
  var reduceMotion: Bool

  private var power: Double { min(1, max(0, meter.averagePower - 0.003) * 50) }

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(0..<7) { index in
        Capsule()
          .fill(Color.accentColor)
          .frame(width: 4, height: 3 + 19 * power * (1 - abs(Double(index - 3)) / 5))
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: power)
  }
}

#Preview("Recording phases — synthetic microphone input") {
  VStack(spacing: 16) {
    TranscriptionIndicatorView(status: .optionKeyPressed, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .recording, meter: .init(averagePower: 0.018, peakPower: 0.025))
    TranscriptionIndicatorView(status: .transcribing, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .postProcessing, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .prewarming, meter: .init(averagePower: 0, peakPower: 0))
  }
  .padding(32)
}
