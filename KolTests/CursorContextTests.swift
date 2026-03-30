import Testing
@testable import KolCore

@Suite("CursorContext.flatText")
struct CursorContextTests {

	@Test("flatText with all fields populated")
	func flatTextAllFields() {
		let ctx = CursorContext(
			beforeCursor: "abc", afterCursor: "xyz",
			selectedText: "sel", isTerminal: false
		)
		#expect(ctx.flatText == "abcselxyz")
	}

	@Test("flatText with only beforeCursor")
	func flatTextOnlyBefore() {
		let ctx = CursorContext(
			beforeCursor: "abc", afterCursor: "",
			selectedText: nil, isTerminal: false
		)
		#expect(ctx.flatText == "abc")
	}

	@Test("flatText with only selectedText")
	func flatTextOnlySelected() {
		let ctx = CursorContext(
			beforeCursor: "", afterCursor: "",
			selectedText: "sel", isTerminal: false
		)
		#expect(ctx.flatText == "sel")
	}

	@Test("flatText with empty fields")
	func flatTextEmpty() {
		let ctx = CursorContext(
			beforeCursor: "", afterCursor: "",
			selectedText: nil, isTerminal: false
		)
		#expect(ctx.flatText == "")
	}

	@Test("flatText without selectedText concatenates before and after")
	func flatTextNoSelection() {
		let ctx = CursorContext(
			beforeCursor: "abc", afterCursor: "xyz",
			selectedText: nil, isTerminal: false
		)
		#expect(ctx.flatText == "abcxyz")
	}
}
