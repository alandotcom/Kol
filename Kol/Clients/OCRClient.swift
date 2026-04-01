import Dependencies
import Foundation
import KolCore
import ScreenCaptureKit
import Vision

private let logger = KolLog.screenContext

extension OCRClient: DependencyKey {
	public static var liveValue: Self {
		Self(
			captureWindowText: { pid in
				await captureAndOCR(pid: pid)
			}
		)
	}

	/// Maximum characters to return from OCR (matches ScreenContextClient.maxContextLength).
	private static let maxOCRLength = 3000

	private static func captureAndOCR(pid: pid_t) async -> String? {
		do {
			// 1. Find the window for this PID
			let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
			guard let window = content.windows.first(where: {
				$0.owningApplication?.processID == pid
			}) else {
				logger.debug("OCR: no on-screen window found for pid \(pid)")
				return nil
			}

			// 2. Capture screenshot at 1x resolution (sufficient for Vision OCR,
			//    uses 4x less memory than retina on HiDPI displays)
			let filter = SCContentFilter(desktopIndependentWindow: window)
			let config = SCStreamConfiguration()
			config.width = Int(window.frame.width)
			config.height = Int(window.frame.height)

			let image = try await SCScreenshotManager.captureImage(
				contentFilter: filter,
				configuration: config
			)

			// Bail out if the task was cancelled during screenshot capture
			guard !Task.isCancelled else {
				logger.debug("OCR: cancelled after screenshot for pid \(pid)")
				return nil
			}

			// 3. Run Vision OCR with accurate recognition (proper name spelling matters
			//    more than speed — OCR runs every ~3s and feeds vocabulary extraction)
			let request = VNRecognizeTextRequest()
			request.recognitionLevel = .accurate

			let handler = VNImageRequestHandler(cgImage: image)
			try handler.perform([request])

			guard let observations = request.results, !observations.isEmpty else {
				logger.debug("OCR: no text recognized for pid \(pid)")
				return nil
			}

			// 4. Extract top candidates and join
			let lines = observations.compactMap { $0.topCandidates(1).first?.string }
			let text = lines.joined(separator: "\n")

			// 5. Truncate to max length
			let result: String
			if text.count > maxOCRLength {
				result = String(text.prefix(maxOCRLength))
			} else {
				result = text
			}

			logger.info("OCR: captured \(lines.count) lines, \(result.count) chars for pid \(pid)")
			return result

		} catch {
			logger.error("OCR: capture failed for pid \(pid): \(error.localizedDescription)")
			return nil
		}
	}
}
