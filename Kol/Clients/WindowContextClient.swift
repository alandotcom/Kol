import AXorcist
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
				MainActor.assumeIsolated { readWindowTitle(pid: pid) }
			},
			browserURL: { pid in
				MainActor.assumeIsolated { extractBrowserURL(pid: pid) }
			},
			messagingParticipants: { pid in
				MainActor.assumeIsolated { extractParticipantNames(pid: pid) }
			}
		)
	}

	// MARK: - Window Title

	@MainActor
	private static func readWindowTitle(pid: pid_t) -> String? {
		guard let app = Element.application(for: pid),
			  let window = app.focusedWindow(),
			  let title = window.title(), !title.isEmpty
		else { return nil }

		logger.debug("WindowContext: windowTitle(\(pid)) = \"\(title, privacy: .private)\"")
		return title
	}

	// MARK: - Browser URL

	/// Walk the AX tree looking for a text field containing a URL.
	/// Browsers expose the address bar as an AXTextField or AXComboBox with a URL value.
	@MainActor
	private static func extractBrowserURL(pid: pid_t) -> String? {
		guard let app = Element.application(for: pid),
			  let window = app.focusedWindow()
		else { return nil }

		var nodeCount = 0
		let result = searchForURL(element: window, depth: 0, maxDepth: 4, nodeCount: &nodeCount, maxNodes: 100)
		if let result {
			logger.debug("WindowContext: browserURL(\(pid)) = \"\(result, privacy: .private)\"")
		} else {
			logger.debug("WindowContext: browserURL(\(pid)) = nil (no URL found at depth ≤4, ≤100 nodes)")
		}
		return result
	}

	@MainActor
	private static func searchForURL(
		element: Element,
		depth: Int,
		maxDepth: Int,
		nodeCount: inout Int,
		maxNodes: Int
	) -> String? {
		guard depth < maxDepth, nodeCount < maxNodes else { return nil }

		let role = element.role()

		// URL bars are typically AXTextField, AXComboBox, or AXStaticText
		if role == "AXTextField" || role == "AXComboBox" {
			if let value = element.stringValue(), looksLikeURL(value) {
				return value
			}
		}

		// Recurse into children
		guard let children = element.children() else { return nil }

		nodeCount += 1
		for child in children {
			if let url = searchForURL(element: child, depth: depth + 1, maxDepth: maxDepth, nodeCount: &nodeCount, maxNodes: maxNodes) {
				return url
			}
		}
		return nil
	}

	private static func looksLikeURL(_ value: String) -> Bool {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
			|| (trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count > 4)
	}

	// MARK: - Messaging Participants

	/// Walk the AX tree looking for sender-like text elements in messaging apps.
	/// Heuristic: AXStaticText elements that look like person names.
	@MainActor
	private static func extractParticipantNames(pid: pid_t) -> [String] {
		guard let app = Element.application(for: pid),
			  let window = app.focusedWindow()
		else { return [] }

		var names: [String] = []
		var seen = Set<String>()
		collectParticipantNames(element: window, depth: 0, maxDepth: 5, nodeCount: 0, maxNodes: 500, names: &names, seen: &seen)

		if !names.isEmpty {
			logger.debug("WindowContext: found \(names.count) participant name(s) for pid \(pid): \(names.joined(separator: ", "), privacy: .private)")
		} else {
			logger.debug("WindowContext: no participant names found for pid \(pid)")
		}
		return Array(names.prefix(20))
	}

	@MainActor
	private static func collectParticipantNames(
		element: Element,
		depth: Int,
		maxDepth: Int,
		nodeCount: Int,
		maxNodes: Int,
		names: inout [String],
		seen: inout Set<String>
	) {
		guard depth < maxDepth, nodeCount < maxNodes else { return }

		let role = element.role()

		// Look for static text that could be a sender name
		if role == "AXStaticText" || role == "AXHeading" {
			if let value = element.stringValue() ?? element.title() {
				if NameParser.looksLikePersonName(value) {
					if seen.insert(value).inserted {
						names.append(value)
					}
				} else if value.count >= 2, value.count <= 40, !value.contains("\n") {
					logger.debug("WindowContext: rejected name candidate: \"\(value, privacy: .private)\" (role=\(role ?? "?"))")
				}
			}
		}

		// Check button descriptions for "Includes X and Y" patterns (Slack member lists)
		if role == "AXButton" {
			if let desc = element.descriptionText(), desc.contains("Includes") {
				let parsed = NameParser.parseNamesFromDescription(desc)
				for name in parsed {
					if seen.insert(name).inserted {
						names.append(name)
						logger.debug("WindowContext: found name in button description: \"\(name, privacy: .private)\"")
					}
				}
			}
		}

		// Recurse into children
		guard let children = element.children() else { return }

		var count = nodeCount + 1
		for child in children {
			collectParticipantNames(
				element: child, depth: depth + 1, maxDepth: maxDepth,
				nodeCount: count, maxNodes: maxNodes, names: &names, seen: &seen
			)
			count += 1
		}
	}

}

extension DependencyValues {
	var windowContext: WindowContextClient {
		get { self[WindowContextClient.self] }
		set { self[WindowContextClient.self] = newValue }
	}
}
