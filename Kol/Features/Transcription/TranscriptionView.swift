import ComposableArchitecture
import Inject
import SwiftUI

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  @State private var showCompleted = false
  /// Incremented each time a completion flash should trigger; drives .task(id:) auto-cancellation.
  @State private var completionFlashID = 0

  private var storeStatus: TranscriptionIndicatorView.Status {
    if store.isTranscribing {
      return .transcribing
    } else if store.isRecording {
      return .recording
    } else if store.isPostProcessing {
      return .postProcessing
    } else if store.isPrewarming {
      return .prewarming
    } else {
      return .hidden
    }
  }

  private var visualStatus: TranscriptionIndicatorView.Status {
    if showCompleted { return .completed }
    return storeStatus
  }

  var body: some View {
    TranscriptionIndicatorView(
      status: visualStatus,
      meter: store.meter
    )
    .onChange(of: storeStatus) { oldStatus, newStatus in
      if (oldStatus == .transcribing || oldStatus == .prewarming || oldStatus == .postProcessing) && newStatus == .hidden {
        showCompleted = true
        completionFlashID += 1
      } else if newStatus == .recording {
        showCompleted = false
      }
    }
    .task(id: completionFlashID) {
      guard completionFlashID > 0 else { return }
      try? await Task.sleep(for: .milliseconds(600))
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        showCompleted = false
      } else {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
          showCompleted = false
        }
      }
    }
    .task {
      await store.send(.task).finish()
    }
    .enableInjection()
  }
}
