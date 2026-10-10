import Dependencies
import DependenciesMacros
import Foundation

/// Captures window screenshots via ScreenCaptureKit and extracts text via Vision OCR.
/// Prioritizes vocabulary near the insertion caret or focused control.
@DependencyClient
public struct OCRClient: Sendable {
	/// Capture the active target window and return nearby vocabulary in proximity order.
	/// Returns nil if Screen Recording permission is not granted, the window can't be found,
	/// or OCR produces no results.
	public var captureWindowVocabulary: @Sendable (_ pid: pid_t) async -> [String]? = { _ in nil }
}

extension OCRClient: TestDependencyKey {
	public static let testValue = OCRClient()
}

public extension DependencyValues {
	var ocrClient: OCRClient {
		get { self[OCRClient.self] }
		set { self[OCRClient.self] = newValue }
	}
}
