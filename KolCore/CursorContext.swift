import Foundation

/// Structured text context around the user's cursor position.
/// Replaces the flat string from `captureVisibleText()` with positional awareness.
public struct CursorContext: Sendable, Equatable {
	/// Text before the cursor (up to ~1500 chars, truncated from the front at word boundary).
	public let beforeCursor: String

	/// Text after the cursor (up to ~1500 chars, truncated from the back at word boundary).
	public let afterCursor: String

	/// Currently selected text, or nil if no selection.
	public let selectedText: String?

	/// Whether the source is a terminal emulator (affects prompt preamble).
	public let isTerminal: Bool

	public init(beforeCursor: String, afterCursor: String, selectedText: String?, isTerminal: Bool) {
		self.beforeCursor = beforeCursor
		self.afterCursor = afterCursor
		self.selectedText = selectedText
		self.isTerminal = isTerminal
	}

	/// Reassembled flat string for backward compatibility with `captureVisibleText()`.
	public var flatText: String {
		var parts: [String] = []
		if !beforeCursor.isEmpty { parts.append(beforeCursor) }
		if let sel = selectedText, !sel.isEmpty { parts.append(sel) }
		if !afterCursor.isEmpty { parts.append(afterCursor) }
		return parts.joined()
	}
}
