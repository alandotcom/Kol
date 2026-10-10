import Foundation
import Testing

@testable import KolCore

@Suite
struct TranscriptionFeatureTests {

  @Test("TranscriptionFeature type accessible from KolCore")
  func typeAccessible() {
    let _ = TranscriptionFeature.self
    let _ = TranscriptionFeature.Action.startRecording
    let _ = TranscriptionFeature.Action.cancel
    let _ = TranscriptionFeature.CancelID.session(UUID())
  }
}
