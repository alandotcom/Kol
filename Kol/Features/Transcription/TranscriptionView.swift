import ComposableArchitecture
import Inject
import SwiftUI

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  @State private var showCompleted = false

  private var storeStatus: TranscriptionIndicatorView.Status {
    if store.isTranscribing {
      return .transcribing
    } else if store.isRecording {
      return .recording
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
      if (oldStatus == .transcribing || oldStatus == .prewarming) && newStatus == .hidden {
        showCompleted = true
      } else if newStatus == .recording {
        showCompleted = false
      }
    }
    .task(id: showCompleted) {
      guard showCompleted else { return }
      try? await Task.sleep(for: .milliseconds(600))
      withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
        showCompleted = false
      }
    }
    .task {
      await store.send(.task).finish()
    }
    .enableInjection()
  }
}
