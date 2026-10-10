import Foundation

/// Text read from the focused control. Position is claimed only for a usable range
/// in that control's complete value, before any truncation.
public struct FocusedText: Sendable, Equatable {
  public enum Content: Sendable, Equatable {
    case positioned(before: String, selected: String?, after: String)
    case unpositioned(text: String, selected: String?)
    case selectionOnly(String)
  }

  public let content: Content
  private static let limit = 3000

  public init?(value: String?, selectedRange: NSRange? = nil, selectedText: String? = nil) {
    let selection = selectedText.flatMap(Self.nonblank)
    guard let value, Self.nonblank(value) != nil else {
      guard let selection else { return nil }
      content = .selectionOnly(String(selection.prefix(Self.limit)))
      return
    }

    let utf16 = value.utf16
    if let range = selectedRange,
       range.location >= 0, range.length >= 0,
       range.location <= utf16.count, range.length <= utf16.count - range.location,
       let start = String.Index(utf16.index(utf16.startIndex, offsetBy: range.location), within: value),
       let end = String.Index(utf16.index(utf16.startIndex, offsetBy: range.location + range.length), within: value),
       selection == nil || selection == String(value[start..<end]) {
      let selected = String(value[start..<end].prefix(Self.limit))
      let remaining = Self.limit - selected.count
      let beforeBudget = min(1500, remaining / 2)
      let afterBudget = min(1500, remaining - beforeBudget)
      content = .positioned(
        before: Self.tail(String(value[..<start]), limit: beforeBudget),
        selected: selected.isEmpty ? nil : selected,
        after: Self.head(String(value[end...]), limit: afterBudget)
      )
    } else {
      let selected = selection.map { String($0.prefix(Self.limit)) }
      content = .unpositioned(
        text: Self.tail(value, limit: max(0, Self.limit - (selected?.count ?? 0) - (selected == nil ? 0 : 1))),
        selected: selected
      )
    }
  }

  /// Reading-order text for vocabulary and capture quality, derived from the structure.
  public var plainText: String {
    switch content {
    case let .positioned(before, selected, after):
      return before + (selected ?? "") + after
    case let .unpositioned(text, selected):
      guard let selected, !text.contains(selected) else { return text }
      return text.isEmpty ? selected : text + "\n" + selected
    case let .selectionOnly(text):
      return text
    }
  }

  private static func nonblank(_ text: String) -> String? {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }

  private static func tail(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    let result = String(text.suffix(limit))
    guard let boundary = result.firstIndex(where: \.isWhitespace) else { return result }
    let start = result.index(after: boundary)
    return start < result.endIndex ? String(result[start...]) : result
  }

  private static func head(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    let result = String(text.prefix(limit))
    guard let boundary = result.lastIndex(where: \.isWhitespace), boundary > result.startIndex else { return result }
    return String(result[..<boundary])
  }
}

/// A temporary capture result. Window text supplies vocabulary; only focused text
/// can be retained for the cleanup prompt.
public struct TextSourceSnapshot: Sendable, Equatable {
  public let focused: FocusedText?
  public let surroundingText: String?

  public init?(focused: FocusedText?, surroundingText: String?) {
    let surrounding = surroundingText.flatMap {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String($0.prefix(3000))
    }
    guard focused != nil || surrounding != nil else { return nil }
    self.focused = focused
    self.surroundingText = surrounding
  }

  public var vocabularyTerms: [String] {
    let focusedTerms = focused.map { VocabularyExtractor.extract(from: $0.plainText).allTerms } ?? []
    let surroundingTerms = surroundingText.map { VocabularyExtractor.extract(from: $0).allTerms } ?? []
    var seen = Set<String>()
    return (focusedTerms + surroundingTerms).filter { seen.insert($0.lowercased()).inserted }
  }

  /// The existing remote name request gets a bounded share of each AX source.
  public var vocabularySourceText: String? {
    let sources = [focused?.plainText, surroundingText].compactMap { $0 }.filter { !$0.isEmpty }
    guard !sources.isEmpty else { return nil }
    let limit = sources.count == 1 ? 3000 : 1499
    return sources.map { String($0.prefix(limit)) }.joined(separator: "\n")
  }
}
