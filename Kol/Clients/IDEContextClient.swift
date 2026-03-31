import ApplicationServices
import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.screenContext

/// Extracts IDE-specific context (open file names) from the AX tree of code editors.
/// Uses raw AX API to walk the window's toolbar/tab bar and extract tab titles.
@DependencyClient
struct IDEContextClient: Sendable {
	/// Extract open file names from the IDE tab bar for the given process.
	var extractTabTitles: @Sendable (_ pid: pid_t) -> [String] = { _ in [] }
}

extension IDEContextClient: DependencyKey {
	static var liveValue: Self {
		Self(
			extractTabTitles: { pid in
				extractTabTitlesFromAXTree(pid: pid)
			}
		)
	}

	/// Walk the AX tree for a process and extract tab titles.
	/// Looks for AXRadioButton or AXTab elements that typically represent editor tabs.
	private static func extractTabTitlesFromAXTree(pid: pid_t) -> [String] {
		let app = AXUIElementCreateApplication(pid)

		// Get the focused/frontmost window
		var windowRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
			  let windowRef
		else {
			logger.debug("IDEContext: failed to get focused window for pid \(pid)")
			return []
		}
		let window = windowRef as! AXUIElement

		// Collect tab-like elements from the window's children (limited depth)
		var titles: [String] = []
		var seen = Set<String>()
		collectTabTitles(element: window, depth: 0, maxDepth: 5, titles: &titles, seen: &seen)

		if !titles.isEmpty {
			logger.debug("IDEContext: found \(titles.count) tab title(s) for pid \(pid)")
		}
		return titles
	}

	/// Recursively search for tab-like elements and extract their titles.
	/// Tab elements in IDEs typically have role AXRadioButton (in tab groups), AXTab, or AXButton
	/// with a title that looks like a filename.
	private static func collectTabTitles(
		element: AXUIElement,
		depth: Int,
		maxDepth: Int,
		titles: inout [String],
		seen: inout Set<String>
	) {
		guard depth < maxDepth else { return }

		let role = axStringAttribute(element, kAXRoleAttribute)
		let subrole = axStringAttribute(element, kAXSubroleAttribute)
		let title = axStringAttribute(element, kAXTitleAttribute)

		// Tab elements in IDEs:
		// - VS Code / Cursor (Electron): AXRadioButton inside AXTabGroup with title = filename
		// - Xcode: AXRadioButton inside AXTabGroup with title = filename
		// - Zed: AXTab or AXRadioButton with title = filename
		let isTabLike = role == "AXRadioButton" || role == "AXTab"
		let isInTabGroup = subrole == "AXTabButton"

		if (isTabLike || isInTabGroup), let title, !title.isEmpty {
			// Filter to likely file names: must contain a dot (extension) or be a reasonable identifier
			if looksLikeFileName(title), seen.insert(title).inserted {
				titles.append(title)
			}
		}

		// Recurse into children
		var childrenRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
			  let children = childrenRef as? [AXUIElement]
		else { return }

		// Optimization: if we find an AXTabGroup, only search its children (skip the rest of the tree at this level)
		for child in children {
			collectTabTitles(element: child, depth: depth + 1, maxDepth: maxDepth, titles: &titles, seen: &seen)
		}
	}

	/// Heuristic: does this title look like a file name?
	/// Matches "Foo.swift", "package.json", etc. Also accepts titles with path separators.
	private static func looksLikeFileName(_ title: String) -> Bool {
		// Must contain a dot with a short extension
		if let dotIndex = title.lastIndex(of: ".") {
			let ext = title[title.index(after: dotIndex)...]
			return ext.count >= 1 && ext.count <= 6 && !ext.contains(" ")
		}
		return false
	}

}

extension DependencyValues {
	var ideContext: IDEContextClient {
		get { self[IDEContextClient.self] }
		set { self[IDEContextClient.self] = newValue }
	}
}
