import SwiftUI
import ComposableArchitecture
import Dependencies
import AppKit
import Sauce

struct MenuBarCopyLastTranscriptButton: View {
  @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  @Shared(.kolSettings) var kolSettings: KolSettings
  @Dependency(\.pasteboard) var pasteboard

  private var lastText: String? { transcriptionHistory.history.first?.text }

  private var previewText: String {
    guard let text = lastText?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else { return "" }
    return text.count > 40 ? "\(text.prefix(40))…" : text
  }

  var body: some View {
    let button = Button(action: {
      if let text = lastText {
        Task { await pasteboard.paste(text) }
      }
    }) {
      HStack(spacing: 6) {
        Text("Paste Last Transcript")
        if !previewText.isEmpty {
          Text("(\(previewText))")
            .foregroundStyle(.secondary)
        }
      }
    }
    .disabled(lastText == nil)

    if let hotkey = kolSettings.pasteLastTranscriptHotkey,
       let key = hotkey.key,
       let keyEquivalent = toKeyEquivalent(key) {
      button.keyboardShortcut(keyEquivalent, modifiers: toEventModifiers(hotkey.modifiers))
    } else {
      button
    }
  }

  private func toKeyEquivalent(_ key: Key) -> KeyEquivalent? {
    switch key.rawValue {
    case "a": return "a"
    case "b": return "b"
    case "c": return "c"
    case "d": return "d"
    case "e": return "e"
    case "f": return "f"
    case "g": return "g"
    case "h": return "h"
    case "i": return "i"
    case "j": return "j"
    case "k": return "k"
    case "l": return "l"
    case "m": return "m"
    case "n": return "n"
    case "o": return "o"
    case "p": return "p"
    case "q": return "q"
    case "r": return "r"
    case "s": return "s"
    case "t": return "t"
    case "u": return "u"
    case "v": return "v"
    case "w": return "w"
    case "x": return "x"
    case "y": return "y"
    case "z": return "z"
    case "0": return "0"
    case "1": return "1"
    case "2": return "2"
    case "3": return "3"
    case "4": return "4"
    case "5": return "5"
    case "6": return "6"
    case "7": return "7"
    case "8": return "8"
    case "9": return "9"
    case ",": return ","
    case ".": return "."
    case "/": return "/"
    case "\\": return "\\"
    case "'": return "'"
    case ";": return ";"
    case "[": return "["
    case "]": return "]"
    case "-": return "-"
    case "=": return "="
    case "`": return "`"
    default: return nil
    }
  }

  private func toEventModifiers(_ modifiers: Modifiers) -> SwiftUI.EventModifiers {
    var result: SwiftUI.EventModifiers = []
    if modifiers.contains(kind: .command) { result.insert(.command) }
    if modifiers.contains(kind: .option) { result.insert(.option) }
    if modifiers.contains(kind: .shift) { result.insert(.shift) }
    if modifiers.contains(kind: .control) { result.insert(.control) }
    return result
  }
}

#Preview {
  MenuBarCopyLastTranscriptButton()
}
