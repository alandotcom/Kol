import ApplicationServices
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct ScreenContextClient: Sendable {
    var captureVisibleText: @Sendable () -> String? = { nil }
}

extension ScreenContextClient: DependencyKey {
    /// Maximum characters to extract, centered on cursor position.
    private static let maxContextLength = 3000

    static var liveValue: Self {
        Self(
            captureVisibleText: {
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

                // 1. Try selected text first — strongest signal
                var selectedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    focused,
                    kAXSelectedTextAttribute as CFString,
                    &selectedRef
                ) == .success,
                   let selected = selectedRef as? String,
                   !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return String(selected.prefix(maxContextLength))
                }

                // 2. Fall back to full text value
                var valueRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    focused,
                    kAXValueAttribute as CFString,
                    &valueRef
                ) == .success,
                      let fullText = valueRef as? String,
                      !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return nil
                }

                // If text is small enough, return it all
                guard fullText.count > maxContextLength else {
                    return fullText
                }

                // 3. For large content, window around cursor position
                var rangeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    focused,
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

                // No cursor info — take first chunk
                return String(fullText.prefix(maxContextLength))
            }
        )
    }
}

extension DependencyValues {
    var screenContext: ScreenContextClient {
        get { self[ScreenContextClient.self] }
        set { self[ScreenContextClient.self] = newValue }
    }
}
