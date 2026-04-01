import Dependencies
import DependenciesMacros
import Foundation

/// Captures window screenshots via ScreenCaptureKit and extracts text via Vision OCR.
/// Used as a fallback when AX-captured text is too sparse (< 50 chars), which happens
/// for all Electron/Chromium apps (Slack, Discord, Teams, browsers).
@DependencyClient
public struct OCRClient: Sendable {
	/// Capture a window screenshot for the given PID and return OCR-extracted text.
	/// Returns nil if Screen Recording permission is not granted, the window can't be found,
	/// or OCR produces no results.
	public var captureWindowText: @Sendable (_ pid: pid_t) async -> String? = { _ in nil }
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
