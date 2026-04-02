import AXorcist
import Dependencies
import Foundation
import KolCore

private let logger = KolLog.conversation

extension WindowContextClient: DependencyKey {
	public static var liveValue: Self {
		Self(
			windowTitle: { pid in
				MainActor.assumeIsolated { readWindowTitle(pid: pid) }
			},
			browserURL: { pid in
				MainActor.assumeIsolated { extractBrowserURL(pid: pid) }
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

}
