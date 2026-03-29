import ApplicationServices
import Dependencies
import DependenciesMacros
import Foundation

private let logger = KolLog.screenContext

@DependencyClient
struct ScreenContextClient: Sendable {
    var captureVisibleText: @Sendable (_ sourceAppBundleID: String?) -> String? = { _ in nil }
    /// Returns the character immediately before the cursor in the focused text field, or nil.
    var characterBeforeCursor: @Sendable () -> Character? = { nil }
}

extension ScreenContextClient: DependencyKey {
    /// Maximum characters to extract, centered on cursor position.
    private static let maxContextLength = 3000

    /// Terminal bundle IDs — used for tail-windowing (take last N chars instead of first).
    private static let terminalBundleIDs: Set<String> = [
        "com.mitchellh.ghostty", "com.apple.Terminal",
        "com.googlecode.iterm2", "dev.warp.warp-stable",
        "net.kovidgoyal.kitty", "org.alacritty",
    ]

    static var liveValue: Self {
        Self(
            captureVisibleText: { sourceAppBundleID in
                let bundleID = sourceAppBundleID ?? "unknown"
                logger.debug("Capturing screen context for app: \(bundleID, privacy: .public)")

                let systemWide = AXUIElementCreateSystemWide()

                var focusedRef: CFTypeRef?
                let focusStatus = AXUIElementCopyAttributeValue(
                    systemWide,
                    kAXFocusedUIElementAttribute as CFString,
                    &focusedRef
                )
                guard focusStatus == .success, let focusedRef else {
                    logger.warning("Failed to get focused element: \(focusStatus.rawValue)")
                    return nil
                }

                let focused = focusedRef as! AXUIElement
                let role = axStringAttribute(focused, kAXRoleAttribute) ?? "unknown"
                logger.debug("Focused element role: \(role, privacy: .public)")

                // 1. Try selected text first — strongest signal
                if let selected = axStringAttribute(focused, kAXSelectedTextAttribute),
                   !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    logger.info("Got selected text: \(selected.count) chars")
                    return String(selected.prefix(maxContextLength))
                }

                // 2. Try full text value on focused element
                if let text = extractValue(from: focused, sourceAppBundleID: sourceAppBundleID) {
                    logger.info("Got text from focused element: \(text.count) chars")
                    return text
                }

                // 3. Walk children of focused element (for terminals that expose text on child elements)
                if let text = findTextInChildren(of: focused, sourceAppBundleID: sourceAppBundleID) {
                    logger.info("Got text from child element: \(text.count) chars")
                    return text
                }

                // 4. Walk parent chain and try siblings
                if let text = findTextInParentChain(from: focused, sourceAppBundleID: sourceAppBundleID) {
                    logger.info("Got text from parent/sibling: \(text.count) chars")
                    return text
                }

                logger.notice("No text found for \(bundleID, privacy: .public)")
                return nil
            },
            characterBeforeCursor: {
                let systemWide = AXUIElementCreateSystemWide()

                var focusedRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    systemWide,
                    kAXFocusedUIElementAttribute as CFString,
                    &focusedRef
                ) == .success, let focusedRef else {
                    return nil
                }

                let focused = focusedRef as! AXUIElement

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

    /// Read a string attribute from an AX element, returning nil on failure.
    private static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let str = ref as? String
        else { return nil }
        return str
    }

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
                let cursorPos = cfRange.location
                let half = maxContextLength / 2
                let start = max(0, cursorPos - half)
                let end = min(fullText.count, start + maxContextLength)
                let startIndex = fullText.index(fullText.startIndex, offsetBy: start)
                let endIndex = fullText.index(fullText.startIndex, offsetBy: end)
                return String(fullText[startIndex..<endIndex])
            }
        }

        // No cursor info — for terminals, take the tail (recent output); otherwise take the head
        if let id = sourceAppBundleID, terminalBundleIDs.contains(id) {
            return String(fullText.suffix(maxContextLength))
        }
        return String(fullText.prefix(maxContextLength))
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
