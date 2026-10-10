import AppKit
import AXorcist
import Dependencies
import Foundation
import KolCore

private let logger = KolLog.screenContext

extension ScreenContextClient: DependencyKey {
    public static var liveValue: Self {
        Self(capture: { sourceApplication in
            MainActor.assumeIsolated { captureText(from: sourceApplication) }
        })
    }

    @MainActor
    private static func captureText(from sourceApplication: FrontmostApp?) -> TextSourceSnapshot? {
        guard let sourceApplication,
              sourceApplication.processIdentifier > 0,
              !PromptLayers.isTerminal(sourceApplication.bundleIdentifier),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == sourceApplication.processIdentifier
        else {
            logger.debug("AX capture skipped: recorded application is not the active target")
            return nil
        }
        guard let application = Element.application(for: sourceApplication.processIdentifier) else {
            logger.debug("AX capture unavailable: application attributes could not be read; trusted=\(AXIsProcessTrusted())")
            return nil
        }

        let pid = sourceApplication.processIdentifier
        let focused = Element.systemWide().focusedUIElement().flatMap { element -> Element? in
            var ownerPID: pid_t = 0
            guard AXUIElementGetPid(element.underlyingElement, &ownerPID) == .success,
                  ownerPID == pid else { return nil }
            return element
        }

        // Value, range and selected text must all come from this exact element.
        // Text found elsewhere is collected separately and never given this range.
        let focusedText = focused.flatMap { element in
            let value = element.stringValue()
            let range = element.selectedTextRange().map { NSRange(location: $0.location, length: $0.length) }
            let result = FocusedText(value: value, selectedRange: range, selectedText: element.selectedText())
            if let result, case .unpositioned = result.content {
                logger.debug("Focused text has no usable cursor range")
            }
            return result
        }

        let root = application.focusedWindow() ?? focused?.parent() ?? focused
        let surroundingText = root.map { collectVisibleText(from: $0, excluding: focusedText == nil ? nil : focused) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        let snapshot = TextSourceSnapshot(focused: focusedText, surroundingText: surroundingText)
        logger.debug("AX capture: \(focusedText?.plainText.count ?? 0) focused chars, \(snapshot?.surroundingText?.count ?? 0) surrounding chars")
        return snapshot
    }

    @MainActor
    private static func collectVisibleText(from root: Element, excluding focused: Element?) -> String {
        var text = ""
        var nodeCount = 0

        func walk(_ element: Element, depth: Int) {
            guard depth < 20, nodeCount < 500, text.count < 3000,
                  element != focused, element.isHidden() != true else { return }
            nodeCount += 1
            let role = element.role()
            if role == "AXStaticText" || role == "AXHeading" || role == "AXTextArea" || role == "AXTextField" {
                if let value = element.stringValue() ?? element.title(),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count >= 2 {
                    let separator = text.isEmpty ? "" : "\n"
                    text += separator + String(value.prefix(max(0, 3000 - text.count - separator.count)))
                }
            }
            guard let children = element.visibleChildren() ?? element.children() else { return }
            for child in children {
                guard nodeCount < 500, text.count < 3000 else { return }
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        logger.debug("AX window walk: \(nodeCount) nodes, \(text.count) chars")
        return text
    }
}
