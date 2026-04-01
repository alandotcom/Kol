import Foundation
import Testing

@testable import KolCore

/// TranscriptionFeature is now in KolCore and accessible from tests.
/// TestStore tests are blocked by @Shared(.fileStorage) SEGV in non-hosted test bundles
/// (swiftlang/swift#87316). State initialization triggers file I/O via @Shared(.kolSettings)
/// which crashes. Workaround: test pure logic extracted from the reducer, or wait for
/// Swift runtime fix.
@Suite
struct TranscriptionFeatureTests {

  @Test("TranscriptionFeature type accessible from KolCore")
  func typeAccessible() {
    let _ = TranscriptionFeature.self
    let _ = TranscriptionFeature.Action.startRecording
    let _ = TranscriptionFeature.Action.cancel
    let _ = TranscriptionFeature.CancelID.transcription
  }
}
