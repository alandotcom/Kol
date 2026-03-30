import ApplicationServices
import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.editTracking

/// Snapshot of a focused text element's state, used for post-paste edit tracking.
public struct ElementSnapshot: Sendable, Equatable {
	public let hash: Int
	public let text: String

	public init(hash: Int, text: String) {
		self.hash = hash
		self.text = text
	}
}

/// Reads the focused text element for post-paste edit tracking.
@DependencyClient
struct EditTrackingClient: Sendable {
	/// Capture a snapshot of the currently focused text element.
	var captureSnapshot: @Sendable () -> ElementSnapshot? = { nil }

	/// Re-read the focused element's text, verifying it matches the given hash.
	/// Returns nil if the element changed or can't be read.
	var readText: @Sendable (_ expectedHash: Int) -> String? = { _ in nil }
}

extension EditTrackingClient: DependencyKey {
	static var liveValue: Self {
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

	private static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
		var ref: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
			  let str = ref as? String
		else { return nil }
		return str
	}
}

extension DependencyValues {
	var editTracking: EditTrackingClient {
		get { self[EditTrackingClient.self] }
		set { self[EditTrackingClient.self] = newValue }
	}
}
