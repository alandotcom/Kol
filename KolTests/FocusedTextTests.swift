import Foundation
import Testing
@testable import KolCore

@Suite("Focused text ownership and position")
struct FocusedTextTests {
  @Test("An extensionless folder path reaches cleanup vocabulary beside a misspelled draft")
  func folderPathVocabulary() throws {
    let snapshot = try #require(TextSourceSnapshot(
      focused: FocusedText(value: "Coal / clients"),
      surroundingText: "Kol/Clients\nKolCore\nKolTests"
    ))
    #expect(snapshot.vocabularyTerms.contains("Kol"))
    #expect(snapshot.vocabularyTerms.contains("Kol/Clients"))
    let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: nil,
      focusedText: snapshot.focused, vocabularyHints: snapshot.vocabularyTerms)
    #expect(prompt.contains(PromptLayers.vocabularyHints(snapshot.vocabularyTerms)))
    #expect(prompt.contains("Coal / clients"))
  }

  @Test("A short draft keeps its own cursor while window text supplies vocabulary")
  func shortDraftAndWindow() throws {
    let focused = try #require(FocusedText(value: "use draftItem", selectedRange: NSRange(location: 4, length: 0)))
    let window = "WindowOwner sidebarItem\n" + String(repeating: "window text ", count: 250)
    let snapshot = try #require(TextSourceSnapshot(focused: focused, surroundingText: window))
    #expect(focused.content == .positioned(before: "use ", selected: nil, after: "draftItem"))
    #expect(snapshot.vocabularyTerms.contains("draftItem"))
    #expect(snapshot.vocabularyTerms.contains("sidebarItem"))
    let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: nil,
      focusedText: snapshot.focused, vocabularyHints: snapshot.vocabularyTerms)
    #expect(!prompt.contains("window text"))
    #expect(prompt.contains("sidebarItem"))
  }

  @Test("UTF-16 ranges around emoji retain the actual selection")
  func emojiSelection() throws {
    let text = try #require(FocusedText(value: "A😀B", selectedRange: NSRange(location: 1, length: 2)))
    #expect(text.content == .positioned(before: "A", selected: "😀", after: "B"))
    #expect(text.plainText == "A😀B")
    let cursor = try #require(FocusedText(value: "A😀B", selectedRange: NSRange(location: 3, length: 0)))
    #expect(cursor.content == .positioned(before: "A😀", selected: nil, after: "B"))
  }

  @Test("Malformed ranges retain unpositioned text", arguments: [
    NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
    NSRange(location: Int.max, length: Int.max), NSRange(location: 4, length: 1),
    NSRange(location: 2, length: 0)
  ])
  func malformedRange(_ range: NSRange) throws {
    let text = try #require(FocusedText(value: "A😀B", selectedRange: range))
    #expect(text.content == .unpositioned(text: "A😀B", selected: nil))
  }

  @Test("A range inside a combined character cannot claim a cursor position")
  func combinedCharacter() throws {
    let text = try #require(FocusedText(value: "e\u{301}", selectedRange: NSRange(location: 1, length: 0)))
    #expect(text.content == .unpositioned(text: "e\u{301}", selected: nil))
  }

  @Test("A selection with an unavailable range remains independently selected")
  func unpositionedSelection() throws {
    let text = try #require(FocusedText(value: "draft chosenItem", selectedText: "chosenItem"))
    #expect(text.content == .unpositioned(text: "draft chosenItem", selected: "chosenItem"))
    #expect(text.plainText == "draft chosenItem")
    let selection = try #require(FocusedText(value: nil, selectedText: "chosenItem"))
    #expect(selection.content == .selectionOnly("chosenItem"))
    #expect(FocusedText(value: " \n ") == nil)
  }

  @Test("Conflicting selection attributes retain unpositioned text")
  func conflictingSelection() throws {
    let text = try #require(FocusedText(value: "first second", selectedRange: NSRange(location: 0, length: 5), selectedText: "second"))
    #expect(text.content == .unpositioned(text: "first second", selected: "second"))
  }

  @Test("Window-only capture supplies terms without raw prompt context")
  func windowOnly() throws {
    let snapshot = try #require(TextSourceSnapshot(focused: nil, surroundingText: "sidebarItem unrelated window prose"))
    #expect(snapshot.vocabularyTerms.contains("sidebarItem"))
    let prompt = PromptAssembler.systemPrompt(language: "en", sourceApp: nil, customRules: nil,
      focusedText: snapshot.focused, vocabularyHints: snapshot.vocabularyTerms)
    #expect(!prompt.contains("unrelated window prose"))
    #expect(!prompt.contains("--- FOCUSED TEXT ---"))
    #expect(prompt.contains("sidebarItem"))
  }

  @Test("A cursor in a long value is split before any context window is truncated")
  func longValueCursor() throws {
    let before = String(repeating: "padding ", count: 600) + "currentItem "
    let text = try #require(FocusedText(value: before + "afterItem", selectedRange: NSRange(location: before.utf16.count, length: 0)))
    guard case let .positioned(prefix, selected, suffix) = text.content else { Issue.record("Expected position"); return }
    #expect(prefix.hasSuffix("currentItem "))
    #expect(selected == nil)
    #expect(suffix == "afterItem")
    #expect(text.plainText.count <= 3000)
  }

  @Test("Selections and drafts share one total bound")
  func totalBound() throws {
    let value = String(repeating: "x", count: 7000)
    let text = try #require(FocusedText(value: value, selectedRange: NSRange(location: 1000, length: 5000)))
    #expect(text.plainText.count <= 3000)
    let unknown = try #require(FocusedText(value: value, selectedText: String(repeating: "y", count: 4000)))
    #expect(unknown.plainText.count <= 3000)
    let snapshot = try #require(TextSourceSnapshot(focused: text, surroundingText: value))
    #expect(snapshot.surroundingText?.count == 3000)
    #expect((snapshot.vocabularySourceText?.count ?? 0) <= 3000)
  }

  @Test("A full focused value leaves a separate vocabulary budget for surrounding text")
  func separateVocabularyBudgets() throws {
    let focused = FocusedText(value: "focusedItem " + String(repeating: "padding ", count: 230))
    let snapshot = try #require(TextSourceSnapshot(focused: focused, surroundingText: "sidebarItem"))
    #expect(snapshot.vocabularyTerms.contains("focusedItem"))
    #expect(snapshot.vocabularyTerms.contains("sidebarItem"))
  }
}
