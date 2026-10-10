import Sauce
import SwiftUI

struct HotKeyView: View {
    var modifiers: Modifiers
    var key: Key?
    var isActive: Bool

    var body: some View {
        Text(isActive && modifiers.isEmpty && key == nil ? "Type shortcut…" : displayText)
            .monospaced()
            .accessibilityLabel(isActive ? "Waiting for keyboard shortcut" : "Keyboard shortcut: \(displayText)")
    }

    private var displayText: String {
        let value = modifiers.sorted.map(\.stringValue).joined() + (key?.toString ?? "")
        return value.isEmpty ? "Not set" : value
    }
}
