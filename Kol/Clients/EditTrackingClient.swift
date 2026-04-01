import ApplicationServices
import Dependencies
import Foundation
import KolCore

private let logger = KolLog.editTracking

extension EditTrackingClient: DependencyKey {
	public static var liveValue: Self {
		Self(
			captureSnapshot: {
				captureCurrentElementSnapshot()
			},
			readText: { expectedHash in
				readCurrentElementText(expectedHash: expectedHash)
			}
		)
	}

	private static func captureCurrentElementSnapshot() -> ElementSnapshot? {
		let systemWide = AXUIElementCreateSystemWide()
		var focusedRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
			  let focusedRef
		else { return nil }
		let element = focusedRef as! AXUIElement

		guard let text = axStringAttribute(element, kAXValueAttribute) else { return nil }

		let hash = computeElementHash(element)
		return ElementSnapshot(hash: hash, text: text)
	}

	private static func readCurrentElementText(expectedHash: Int) -> String? {
		let systemWide = AXUIElementCreateSystemWide()
		var focusedRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
			  let focusedRef
		else { return nil }
		let element = focusedRef as! AXUIElement

		let hash = computeElementHash(element)
		guard hash == expectedHash else {
			logger.debug("Element hash mismatch: expected \(expectedHash), got \(hash)")
			return nil
		}

		return axStringAttribute(element, kAXValueAttribute)
	}

	/// Compute a hash from the element's role + title + PID for identity tracking.
	private static func computeElementHash(_ element: AXUIElement) -> Int {
		var hasher = Hasher()
		hasher.combine(axStringAttribute(element, kAXRoleAttribute) ?? "")
		hasher.combine(axStringAttribute(element, kAXTitleAttribute) ?? "")

		var pid: pid_t = 0
		AXUIElementGetPid(element, &pid)
		hasher.combine(pid)

		return hasher.finalize()
	}

}
