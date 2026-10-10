import ComposableArchitecture
import Inject
import SwiftUI

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  private var status: TranscriptionIndicatorView.Status {
    if store.isTranscribing { return .transcribing }
    if store.isRecording { return .recording }
    if store.isPostProcessing { return .postProcessing }
    if store.isPrewarming { return .prewarming }
    return .hidden
  }

  var body: some View {
    TranscriptionIndicatorView(status: status, meter: store.meter)
      .onChange(of: status, initial: true) {
        NotificationCenter.default.post(
          name: InvisibleWindow.visibilityNotification,
          object: nil,
          userInfo: ["visible": status != .hidden]
        )
      }
      .enableInjection()
  }
}
