import AppKit
import AXorcist
import Dependencies
import Foundation
import KolCore

private let logger = KolLog.screenContext

extension ScreenContextClient: DependencyKey {
    /// Maximum characters to extract, centered on cursor position.
    private static let maxContextLength = 3000

    /// Terminal bundle IDs — delegates to the shared set in KolCoreConstants.
    private static let terminalBundleIDs = KolCoreConstants.terminalBundleIDs

    /// Gets the focused AX element via the system-wide accessibility object.
    @MainActor
    private static func getFocusedElement(caller: String, bundleID: String) -> Element? {
        let systemWide = Element.systemWide()
        guard let focused = systemWide.focusedUIElement() else {
            logger.warning("\(caller): failed to get focused element for \(bundleID, privacy: .public)")
            return nil
        }
        let role = focused.role() ?? "unknown"
        logger.debug("\(caller): focused element role: \(role, privacy: .public)")
        return focused
    }

    /// Finds text by trying the focused element's value, then children, then parent chain,
    /// then AXorcist deep extraction. If the result is too short (< windowWalkThreshold),
    /// falls back to a window-rooted walk to capture surrounding content.
    @MainActor
    private static func findText(
        from focused: Element,
        sourceAppBundleID: String?
    ) -> String? {
        // 1. Try focused element value
        if let text = focused.stringValue(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.count >= windowWalkThreshold {
            return text
        }
        // 2. Walk children (BFS)
        if let text = findTextInChildren(of: focused, sourceAppBundleID: sourceAppBundleID),
           text.count >= windowWalkThreshold {
            return text
        }
        // 3. Walk parent chain
        if let text = findTextInParentChain(from: focused, sourceAppBundleID: sourceAppBundleID),
           text.count >= windowWalkThreshold {
            return text
        }
        // 4. AXorcist deep text extraction
        if let text = extractTextFromElement(focused, maxDepth: 3),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.count >= windowWalkThreshold {
            let windowed = text.count > maxContextLength ? String(text.prefix(maxContextLength)) : text
            logger.debug("Got text via extractTextFromElement: \(windowed.count) chars")
            return windowed
        }
        // 5. Window-rooted walk — captures text from sibling subtrees
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let app = Element.application(for: pid),
           let window = app.focusedWindow() {
            let windowText = collectVisibleText(from: window, maxDepth: 6, maxNodes: 300)
            if !windowText.isEmpty {
                let windowed = windowText.count > maxContextLength ? String(windowText.prefix(maxContextLength)) : windowText
                logger.debug("Got text via window walk: \(windowed.count) chars")
                return windowed
            }
        }
        // 6. Return short text from earlier steps if we have any
        if let text = focused.stringValue(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return nil
    }

    public static var liveValue: Self {
        Self(
            captureVisibleText: { sourceAppBundleID in
                MainActor.assumeIsolated {
                    captureVisibleTextImpl(sourceAppBundleID)
                }
            },
            captureCursorContext: { sourceAppBundleID in
                MainActor.assumeIsolated {
                    captureCursorContextImpl(sourceAppBundleID)
                }
            }
        )
    }

    // MARK: - Closure Implementations

    /// Minimum chars from focused-element extraction before we try the window walk.
    /// Below this threshold, the focused element likely captured only placeholder/input text
    /// and the real content is in sibling subtrees (common in Electron apps like Slack, Discord).
    private static let windowWalkThreshold = 50

    @MainActor
    private static func captureVisibleTextImpl(_ sourceAppBundleID: String?) -> String? {
        let bundleID = sourceAppBundleID ?? "unknown"
        guard let focused = getFocusedElement(caller: "captureVisibleText", bundleID: bundleID) else {
            return nil
        }

        // 1. Try selected text first — strongest signal
        if let selected = focused.selectedText(),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            logger.info("Got selected text: \(selected.count) chars")
            return String(selected.prefix(maxContextLength))
        }

        // 2. Try focused element and its neighborhood
        var focusedText: String?
        if let text = extractValue(from: focused, sourceAppBundleID: sourceAppBundleID) {
            logger.info("Got text from focused element: \(text.count) chars")
            focusedText = text
        } else if let text = findTextInChildren(of: focused, sourceAppBundleID: sourceAppBundleID) {
            logger.info("Got text from child element: \(text.count) chars")
            focusedText = text
        } else if let text = findTextInParentChain(from: focused, sourceAppBundleID: sourceAppBundleID) {
            logger.info("Got text from parent/sibling: \(text.count) chars")
            focusedText = text
        } else if let text = extractTextFromElement(focused, maxDepth: 3),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.info("Got text via deep extraction: \(text.count) chars")
            focusedText = text.count > maxContextLength ? String(text.prefix(maxContextLength)) : text
        }

        // 3. If focused element gave enough text, return it
        if let focusedText, focusedText.count >= windowWalkThreshold {
            return focusedText
        }

        // 4. Window-rooted walk — for Electron apps (Slack, Discord) where the focused element
        //    is an empty compose box with no useful children. The message content lives in sibling
        //    subtrees of the window. Walk the window's visible children collecting AXStaticText content.
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let app = Element.application(for: pid),
           let window = app.focusedWindow() {
            let windowText = collectVisibleText(from: window, maxDepth: 6, maxNodes: 500)
            logger.debug("Window walk: \(windowText.count, privacy: .private) chars (focused was \(focusedText?.count ?? 0, privacy: .private))")
            if windowText.count > (focusedText?.count ?? 0) {
                let windowed = windowText.count > maxContextLength ? String(windowText.prefix(maxContextLength)) : windowText
                logger.info("Got text via window walk: \(windowed.count) chars (focused was \(focusedText?.count ?? 0))")
                return windowed
            }
        }

        // 5. Return whatever the focused element gave us (even if short), or nil
        if let focusedText {
            return focusedText
        }
        logger.notice("No text found for \(bundleID, privacy: .public)")
        return nil
    }

    /// Walks the AX tree from an element, collecting text content from AXStaticText and text-bearing
    /// elements. Unlike extractTextFromElement (which returns the first text found), this collects
    /// ALL visible text to build a comprehensive context snapshot.
    @MainActor
    private static func collectVisibleText(from root: Element, maxDepth: Int, maxNodes: Int) -> String {
        var texts: [String] = []
        var nodeCount = 0

        func walk(_ element: Element, depth: Int) {
            guard depth < maxDepth, nodeCount < maxNodes else { return }
            nodeCount += 1

            let role = element.role()

            // Collect text from text-bearing elements
            if role == "AXStaticText" || role == "AXHeading" {
                if let value = element.stringValue() ?? element.title(),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   value.count >= 2 {
                    texts.append(value)
                }
            }

            // Prefer visible children to avoid walking off-screen scrollback
            let children = element.visibleChildren() ?? element.children()
            guard let children else { return }
            for child in children {
                guard nodeCount < maxNodes else { return }
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return texts.joined(separator: "\n")
    }

    @MainActor
    private static func captureCursorContextImpl(_ sourceAppBundleID: String?) -> CursorContext? {
        let bundleID = sourceAppBundleID ?? "unknown"
        let isTerminal = sourceAppBundleID.map { terminalBundleIDs.contains($0) } ?? false
        let half = maxContextLength / 2

        guard let focused = getFocusedElement(caller: "captureCursorContext", bundleID: bundleID) else {
            return nil
        }

        let fullText = findText(from: focused, sourceAppBundleID: sourceAppBundleID)

        guard let fullText, !fullText.isEmpty else {
            // No text found — check for selected text as last resort
            if let selected = focused.selectedText(),
               !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CursorContext(
                    beforeCursor: "",
                    afterCursor: "",
                    selectedText: String(selected.prefix(maxContextLength)),
                    isTerminal: isTerminal
                )
            }
            return nil
        }

        // For terminals: skip AX screen context entirely. Terminal AX text is rendered
        // layout (whitespace-padded columns, TUI chrome) that adds noise without helping
        // dictation cleanup. Vocabulary hints (from OCR) provide the useful signal.
        if isTerminal {
            return nil
        }

        // Try to get cursor position from selection range
        if let cfRange = focused.selectedTextRange() {
            // AX API returns UTF-16 code unit offsets — convert via the UTF-16 view
            let utf16 = fullText.utf16
            let clampedStart = max(0, min(cfRange.location, utf16.count))
            let clampedEnd = max(0, min(cfRange.location + cfRange.length, utf16.count))
            let utf16Start = utf16.index(utf16.startIndex, offsetBy: clampedStart)
            let utf16End = utf16.index(utf16.startIndex, offsetBy: clampedEnd)

            let startIdx = String.Index(utf16Start, within: fullText) ?? fullText.startIndex
            let endIdx = String.Index(utf16End, within: fullText) ?? fullText.endIndex

            // Extract selected text
            let selectedText: String? = cfRange.length > 0
                ? String(fullText[startIdx..<endIdx])
                : nil

            // Extract and truncate before/after
            let rawBefore = String(fullText[fullText.startIndex..<startIdx])
            let rawAfter = String(fullText[endIdx..<fullText.endIndex])

            let before = truncateFromFront(rawBefore, maxLength: half)
            let after = truncateFromBack(rawAfter, maxLength: half)

            logger.info("Cursor context: \(before.count) before, \(after.count) after, \(selectedText?.count ?? 0) selected")
            return CursorContext(
                beforeCursor: before,
                afterCursor: after,
                selectedText: selectedText,
                isTerminal: false
            )
        }

        // No cursor info — treat entire text as before-cursor
        let truncated = truncateFromFront(fullText, maxLength: maxContextLength)
        return CursorContext(
            beforeCursor: truncated,
            afterCursor: "",
            selectedText: nil,
            isTerminal: false
        )
    }

    // MARK: - AX Helpers

    /// Extract string value from an element, applying windowing for long text.
    @MainActor
    private static func extractValue(from element: Element, sourceAppBundleID: String?) -> String? {
        guard let fullText = element.stringValue(),
              !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        guard fullText.count > maxContextLength else { return fullText }

        // Try cursor-based windowing
        if let cfRange = element.selectedTextRange() {
            let utf16 = fullText.utf16
            let cursorPos = cfRange.location
            let half = maxContextLength / 2
            let start = max(0, cursorPos - half)
            let end = min(utf16.count, start + maxContextLength)
            let utf16Start = utf16.index(utf16.startIndex, offsetBy: start)
            let utf16End = utf16.index(utf16.startIndex, offsetBy: end)
            let startIndex = String.Index(utf16Start, within: fullText) ?? fullText.startIndex
            let endIndex = String.Index(utf16End, within: fullText) ?? fullText.endIndex
            return String(fullText[startIndex..<endIndex])
        }

        // No cursor info — take the head (most relevant for document-like apps)
        // Terminal text is excluded upstream (captureCursorContextImpl returns nil).
        return String(fullText.prefix(maxContextLength))
    }

    /// Truncate a string from the front, keeping the last `maxLength` characters.
    /// Tries to break at a word boundary.
    private static func truncateFromFront(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let suffix = String(text.suffix(maxLength))
        // Find first whitespace to break at word boundary
        if let spaceIdx = suffix.firstIndex(where: { $0.isWhitespace || $0.isNewline }) {
            let nextIdx = suffix.index(after: spaceIdx)
            if nextIdx < suffix.endIndex {
                return String(suffix[nextIdx...])
            }
        }
        return suffix
    }

    /// Truncate a string from the back, keeping the first `maxLength` characters.
    /// Tries to break at a word boundary.
    private static func truncateFromBack(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let prefix = String(text.prefix(maxLength))
        // Find last whitespace to break at word boundary
        if let spaceIdx = prefix.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            return String(prefix[prefix.startIndex..<spaceIdx])
        }
        return prefix
    }

    /// BFS over children to find text-bearing elements. Caps at ~50 elements.
    @MainActor
    private static func findTextInChildren(
        of element: Element,
        sourceAppBundleID: String?,
        maxDepth: Int = 3
    ) -> String? {
        var queue: [(Element, Int)] = [(element, 0)]
        var inspected = 0
        let maxInspected = 50

        while !queue.isEmpty && inspected < maxInspected {
            let (current, depth) = queue.removeFirst()
            guard depth <= maxDepth else { continue }

            guard let children = current.children() else { continue }

            // Sort children: prioritize text-bearing roles
            let prioritized = children.sorted { a, _ in
                let r = a.role() ?? ""
                return r == "AXTextArea" || r == "AXTextField" || r == "AXStaticText"
            }

            for child in prioritized {
                inspected += 1
                if inspected > maxInspected { break }

                if let text = extractValue(from: child, sourceAppBundleID: sourceAppBundleID) {
                    let childRole = child.role() ?? "unknown"
                    logger.debug("Found text on child role=\(childRole, privacy: .public) depth=\(depth + 1)")
                    return text
                }

                if depth + 1 <= maxDepth {
                    queue.append((child, depth + 1))
                }
            }
        }

        return nil
    }

    /// Walk up the parent chain trying to extract text at each level + searching siblings.
    @MainActor
    private static func findTextInParentChain(
        from element: Element,
        sourceAppBundleID: String?,
        maxLevels: Int = 3
    ) -> String? {
        var current = element

        for level in 1...maxLevels {
            guard let parent = current.parent() else { break }

            // Try text on the parent itself
            if let text = extractValue(from: parent, sourceAppBundleID: sourceAppBundleID) {
                logger.debug("Found text on parent level=\(level)")
                return text
            }

            // Try children of parent (siblings of current element)
            if let text = findTextInChildren(of: parent, sourceAppBundleID: sourceAppBundleID, maxDepth: 1) {
                logger.debug("Found text on sibling at parent level=\(level)")
                return text
            }

            current = parent
        }

        return nil
    }
}
