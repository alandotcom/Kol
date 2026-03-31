import ApplicationServices
import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.screenContext

@DependencyClient
struct ScreenContextClient: Sendable {
    var captureVisibleText: @Sendable (_ sourceAppBundleID: String?) -> String? = { _ in nil }
    /// Returns structured text around the cursor (before/after/selected), or nil on failure.
    var captureCursorContext: @Sendable (_ sourceAppBundleID: String?) -> CursorContext? = { _ in nil }
    /// Returns the character immediately before the cursor in the focused text field, or nil.
    var characterBeforeCursor: @Sendable () -> Character? = { nil }
}

extension ScreenContextClient: DependencyKey {
    /// Maximum characters to extract, centered on cursor position.
    private static let maxContextLength = 3000

    /// Terminal bundle IDs — delegates to the shared set in KolCoreConstants.
    private static let terminalBundleIDs = KolCoreConstants.terminalBundleIDs

    /// Gets the focused AX element via the system-wide accessibility object.
    /// Returns nil (and logs) if the focused element cannot be obtained.
    private static func getFocusedElement(caller: String, bundleID: String) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusStatus == .success, let focusedRef else {
            logger.warning("\(caller): failed to get focused element for \(bundleID, privacy: .public) (status \(focusStatus.rawValue))")
            return nil
        }

        let focused = focusedRef as! AXUIElement
        let role = axStringAttribute(focused, kAXRoleAttribute) ?? "unknown"
        logger.debug("\(caller): focused element role: \(role, privacy: .public)")
        return focused
    }

    /// Finds text by trying the focused element's value, then children, then parent chain.
    /// Returns the raw (un-windowed) text, or nil if nothing found.
    private static func findText(
        from focused: AXUIElement,
        sourceAppBundleID: String?
    ) -> String? {
        // 1. Try focused element value
        if let text = axStringAttribute(focused, kAXValueAttribute),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // 2. Walk children
        if let text = findTextInChildren(of: focused, sourceAppBundleID: sourceAppBundleID) {
            return text
        }
        // 3. Walk parent chain
        if let text = findTextInParentChain(from: focused, sourceAppBundleID: sourceAppBundleID) {
            return text
        }
        return nil
    }

    static var liveValue: Self {
        Self(
            captureVisibleText: { sourceAppBundleID in
                let bundleID = sourceAppBundleID ?? "unknown"
                guard let focused = getFocusedElement(caller: "captureVisibleText", bundleID: bundleID) else {
                    return nil
                }

                // 1. Try selected text first — strongest signal
                if let selected = axStringAttribute(focused, kAXSelectedTextAttribute),
                   !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    logger.info("Got selected text: \(selected.count) chars")
                    return String(selected.prefix(maxContextLength))
                }

                // 2. Try full text via AX traversal (value, children, parents)
                if let text = extractValue(from: focused, sourceAppBundleID: sourceAppBundleID) {
                    logger.info("Got text from focused element: \(text.count) chars")
                    return text
                }
                if let text = findTextInChildren(of: focused, sourceAppBundleID: sourceAppBundleID) {
                    logger.info("Got text from child element: \(text.count) chars")
                    return text
                }
                if let text = findTextInParentChain(from: focused, sourceAppBundleID: sourceAppBundleID) {
                    logger.info("Got text from parent/sibling: \(text.count) chars")
                    return text
                }

                logger.notice("No text found for \(bundleID, privacy: .public)")
                return nil
            },
            captureCursorContext: { sourceAppBundleID in
                let bundleID = sourceAppBundleID ?? "unknown"
                let isTerminal = sourceAppBundleID.map { terminalBundleIDs.contains($0) } ?? false
                let half = maxContextLength / 2

                guard let focused = getFocusedElement(caller: "captureCursorContext", bundleID: bundleID) else {
                    return nil
                }

                let fullText = findText(from: focused, sourceAppBundleID: sourceAppBundleID)

                guard let fullText, !fullText.isEmpty else {
                    // No text found — check for selected text as last resort
                    if let selected = axStringAttribute(focused, kAXSelectedTextAttribute),
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

                // For terminals: no reliable cursor position — return tail as beforeCursor
                if isTerminal {
                    let tail = String(fullText.suffix(maxContextLength))
                    return CursorContext(
                        beforeCursor: tail,
                        afterCursor: "",
                        selectedText: nil,
                        isTerminal: true
                    )
                }

                // Try to get cursor position from selection range
                var rangeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    focused,
                    kAXSelectedTextRangeAttribute as CFString,
                    &rangeRef
                ) == .success, let rangeRef {
                    var cfRange = CFRange(location: 0, length: 0)
                    if AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) {
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
                }

                // No cursor info — treat entire text as before-cursor
                let truncated = truncateFromFront(fullText, maxLength: maxContextLength)
                return CursorContext(
                    beforeCursor: truncated,
                    afterCursor: "",
                    selectedText: nil,
                    isTerminal: false
                )
            },
            characterBeforeCursor: {
                guard let focused = getFocusedElement(caller: "characterBeforeCursor", bundleID: "n/a") else {
                    return nil
                }

                // Strategy 1: Use parameterized attribute to read char before cursor (text editors)
                var rangeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    focused,
                    kAXSelectedTextRangeAttribute as CFString,
                    &rangeRef
                ) == .success, let rangeRef {
                    var cfRange = CFRange(location: 0, length: 0)
                    if AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange),
                       cfRange.location > 0 {
                        var charRange = CFRange(location: cfRange.location - 1, length: 1)
                        if let axRange = AXValueCreate(.cfRange, &charRange) {
                            var charRef: CFTypeRef?
                            if AXUIElementCopyParameterizedAttributeValue(
                                focused,
                                kAXStringForRangeParameterizedAttribute as CFString,
                                axRange,
                                &charRef
                            ) == .success, let charStr = charRef as? String, let char = charStr.first {
                                return char
                            }
                        }
                    }
                }

                // For terminals: AX parameterized attributes aren't supported,
                // so characterBeforeCursor returns nil. This is correct — terminal
                // buffers mix user input with command output, making reliable
                // cursor-position detection impossible.
                return nil
            }
        )
    }

    // MARK: - AX Helpers

    /// Extract `kAXValueAttribute` text from an element, applying windowing.
    private static func extractValue(from element: AXUIElement, sourceAppBundleID: String?) -> String? {
        guard let fullText = axStringAttribute(element, kAXValueAttribute),
              !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        guard fullText.count > maxContextLength else { return fullText }

        // Try cursor-based windowing
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef {
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) {
                // AX API returns UTF-16 code unit offsets — convert via the UTF-16 view
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
        }

        // No cursor info — for terminals, take the tail (recent output); otherwise take the head
        if let id = sourceAppBundleID, terminalBundleIDs.contains(id) {
            return String(fullText.suffix(maxContextLength))
        }
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
    private static func findTextInChildren(
        of element: AXUIElement,
        sourceAppBundleID: String?,
        maxDepth: Int = 3
    ) -> String? {
        var queue: [(AXUIElement, Int)] = [(element, 0)]
        var inspected = 0
        let maxInspected = 50

        while !queue.isEmpty && inspected < maxInspected {
            let (current, depth) = queue.removeFirst()
            guard depth <= maxDepth else { continue }

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXChildrenAttribute as CFString,
                &childrenRef
            ) == .success, let children = childrenRef as? [AXUIElement]
            else { continue }

            // Sort children: prioritize text-bearing roles
            let prioritized = children.sorted { a, _ in
                let r = axStringAttribute(a, kAXRoleAttribute) ?? ""
                return r == "AXTextArea" || r == "AXTextField" || r == "AXStaticText"
            }

            for child in prioritized {
                inspected += 1
                if inspected > maxInspected { break }

                if let text = extractValue(from: child, sourceAppBundleID: sourceAppBundleID) {
                    let childRole = axStringAttribute(child, kAXRoleAttribute) ?? "unknown"
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
    private static func findTextInParentChain(
        from element: AXUIElement,
        sourceAppBundleID: String?,
        maxLevels: Int = 3
    ) -> String? {
        var current = element

        for level in 1...maxLevels {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parentRef
            ) == .success, let parentRef
            else { break }

            let parent = parentRef as! AXUIElement

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

extension DependencyValues {
    var screenContext: ScreenContextClient {
        get { self[ScreenContextClient.self] }
        set { self[ScreenContextClient.self] = newValue }
    }
}
