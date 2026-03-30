import ApplicationServices
import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.conversation

/// Extracts window-level metadata from the AX tree: window title, browser URL, and messaging participant names.
/// Used for conversation awareness (§5) and app context reclassification (§10).
@DependencyClient
struct WindowContextClient: Sendable {
	/// Read the title of the focused window for a process.
	var windowTitle: @Sendable (_ pid: pid_t) -> String? = { _ in nil }

	/// Extract a URL from a browser's AX tree (address bar content).
	var browserURL: @Sendable (_ pid: pid_t) -> String? = { _ in nil }

	/// Extract participant names from a messaging app's AX tree.
	/// Best-effort: walks the AX tree looking for sender-like text elements.
	var messagingParticipants: @Sendable (_ pid: pid_t) -> [String] = { _ in [] }
}

extension WindowContextClient: DependencyKey {
	static var liveValue: Self {
		Self(
			windowTitle: { pid in
				readWindowTitle(pid: pid)
			},
			browserURL: { pid in
				extractBrowserURL(pid: pid)
			},
			messagingParticipants: { pid in
				extractParticipantNames(pid: pid)
			}
		)
	}

	// MARK: - Window Title

	private static func readWindowTitle(pid: pid_t) -> String? {
		let app = AXUIElementCreateApplication(pid)
		var windowRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
			  let windowRef
		else { return nil }
		let window = windowRef as! AXUIElement

		var titleRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
			  let title = titleRef as? String, !title.isEmpty
		else { return nil }

		return title
	}

	// MARK: - Browser URL

	/// Walk the AX tree looking for a text field containing a URL.
	/// Browsers expose the address bar as an AXTextField or AXComboBox with a URL value.
	private static func extractBrowserURL(pid: pid_t) -> String? {
		let app = AXUIElementCreateApplication(pid)
		var windowRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
			  let windowRef
		else { return nil }
		let window = windowRef as! AXUIElement

		var result: String?
		searchForURL(element: window, depth: 0, maxDepth: 4, nodeCount: 0, maxNodes: 100, result: &result)
		return result
	}

	private static func searchForURL(
		element: AXUIElement,
		depth: Int,
		maxDepth: Int,
		nodeCount: Int,
		maxNodes: Int,
		result: inout String?
	) {
		guard depth < maxDepth, nodeCount < maxNodes, result == nil else { return }

		let role = axStringAttribute(element, kAXRoleAttribute)

		// URL bars are typically AXTextField, AXComboBox, or AXStaticText
		if role == "AXTextField" || role == "AXComboBox" {
			if let value = axStringAttribute(element, kAXValueAttribute), looksLikeURL(value) {
				result = value
				return
			}
		}

		// Recurse into children
		var childrenRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
			  let children = childrenRef as? [AXUIElement]
		else { return }

		var count = nodeCount + 1
		for child in children {
			searchForURL(element: child, depth: depth + 1, maxDepth: maxDepth, nodeCount: count, maxNodes: maxNodes, result: &result)
			count += 1
			if result != nil { return }
		}
	}

	private static func looksLikeURL(_ value: String) -> Bool {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
			|| (trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count > 4)
	}

	// MARK: - Messaging Participants

	/// Walk the AX tree looking for sender-like text elements in messaging apps.
	/// Heuristic: AXStaticText elements that look like person names (capitalized, 2-30 chars).
	private static func extractParticipantNames(pid: pid_t) -> [String] {
		let app = AXUIElementCreateApplication(pid)
		var windowRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
			  let windowRef
		else { return [] }
		let window = windowRef as! AXUIElement

		var names: [String] = []
		var seen = Set<String>()
		collectParticipantNames(element: window, depth: 0, maxDepth: 5, nodeCount: 0, maxNodes: 500, names: &names, seen: &seen)

		if !names.isEmpty {
			logger.debug("WindowContext: found \(names.count) participant name(s) for pid \(pid)")
		}
		return Array(names.prefix(20))
	}

	private static func collectParticipantNames(
		element: AXUIElement,
		depth: Int,
		maxDepth: Int,
		nodeCount: Int,
		maxNodes: Int,
		names: inout [String],
		seen: inout Set<String>
	) {
		guard depth < maxDepth, nodeCount < maxNodes else { return }

		let role = axStringAttribute(element, kAXRoleAttribute)

		// Look for static text that could be a sender name
		if role == "AXStaticText" || role == "AXHeading" {
			if let value = axStringAttribute(element, kAXValueAttribute) ?? axStringAttribute(element, kAXTitleAttribute),
			   looksLikePersonName(value), seen.insert(value).inserted {
				names.append(value)
			}
		}

		// Recurse into children
		var childrenRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
			  let children = childrenRef as? [AXUIElement]
		else { return }

		var count = nodeCount + 1
		for child in children {
			collectParticipantNames(
				element: child, depth: depth + 1, maxDepth: maxDepth,
				nodeCount: count, maxNodes: maxNodes, names: &names, seen: &seen
			)
			count += 1
		}
	}

	/// Heuristic: does this text look like a person's name?
	/// Must start with uppercase, be 2-30 chars, contain only letters/spaces/hyphens/apostrophes.
	private static let namePattern: NSRegularExpression = {
		try! NSRegularExpression(pattern: #"^[A-Z][a-z]+(?:[\s'-][A-Z]?[a-z]+)*$"#)
	}()

	private static func looksLikePersonName(_ text: String) -> Bool {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count >= 2, trimmed.count <= 30 else { return false }
		let range = NSRange(trimmed.startIndex..., in: trimmed)
		return namePattern.firstMatch(in: trimmed, range: range) != nil
	}

	// MARK: - Helpers

	private static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
		var ref: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
			  let str = ref as? String
		else { return nil }
		return str
	}
}

extension DependencyValues {
	var windowContext: WindowContextClient {
		get { self[WindowContextClient.self] }
		set { self[WindowContextClient.self] = newValue }
	}
}
