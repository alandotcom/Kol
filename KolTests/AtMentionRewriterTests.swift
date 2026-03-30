import Testing
@testable import KolCore

@Suite("AtMentionRewriter")
struct AtMentionRewriterTests {
	@Test("at Name replaced with @Name for known participant")
	func basicRewrite() {
		let result = AtMentionRewriter.rewrite("at Sarah can you review this", knownNames: ["Sarah"])
		#expect(result == "@Sarah can you review this")
	}

	@Test("At Name with capital A also works")
	func capitalAt() {
		let result = AtMentionRewriter.rewrite("At Mike what do you think", knownNames: ["Mike"])
		#expect(result == "@Mike what do you think")
	}

	@Test("at followed by non-name word is not rewritten")
	func nonNameNotRewritten() {
		let result = AtMentionRewriter.rewrite("at the store", knownNames: ["Sarah", "Mike"])
		#expect(result == "at the store")
	}

	@Test("Multiple mentions in one string")
	func multipleMentions() {
		let result = AtMentionRewriter.rewrite("at Sarah and at Bob please review", knownNames: ["Sarah", "Bob"])
		#expect(result == "@Sarah and @Bob please review")
	}

	@Test("Empty known names returns original text")
	func emptyNames() {
		let result = AtMentionRewriter.rewrite("at Sarah hello", knownNames: [])
		#expect(result == "at Sarah hello")
	}

	@Test("Name not in known list is not rewritten")
	func unknownName() {
		let result = AtMentionRewriter.rewrite("at Charlie can you help", knownNames: ["Sarah", "Mike"])
		#expect(result == "at Charlie can you help")
	}

	@Test("Already-mentioned @ not doubled")
	func noDoubleAt() {
		let result = AtMentionRewriter.rewrite("@Sarah hello", knownNames: ["Sarah"])
		#expect(result == "@Sarah hello")
	}
}
