import AXorcist
import Dependencies
import Foundation
import KolCore

private let logger = KolLog.editTracking

extension EditTrackingClient: DependencyKey {
	public static var liveValue: Self {
		Self(
			captureSnapshot: {
				MainActor.assumeIsolated { captureCurrentElementSnapshot() }
			},
			readText: { expectedHash in
				MainActor.assumeIsolated { readCurrentElementText(expectedHash: expectedHash) }
			}
		)
	}

	@MainActor
	private static func captureCurrentElementSnapshot() -> ElementSnapshot? {
		guard let focused = Element.systemWide().focusedUIElement() else { return nil }
		guard let text = focused.stringValue(),
			  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else { return nil }

		let hash = computeElementHash(focused)
		return ElementSnapshot(hash: hash, text: text)
	}

	@MainActor
	private static func readCurrentElementText(expectedHash: Int) -> String? {
		guard let focused = Element.systemWide().focusedUIElement() else { return nil }

		let hash = computeElementHash(focused)
		guard hash == expectedHash else {
			logger.debug("Element hash mismatch: expected \(expectedHash), got \(hash)")
			return nil
		}

		return focused.stringValue()
	}

	/// Compute a hash from the element's role + title + PID for identity tracking.
	@MainActor
	private static func computeElementHash(_ element: Element) -> Int {
		var hasher = Hasher()
		hasher.combine(element.role() ?? "")
		hasher.combine(element.title() ?? "")
		hasher.combine(element.pid() ?? 0)
		return hasher.finalize()
	}

}
