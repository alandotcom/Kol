import Foundation
import Testing
@testable import KolCore

@Suite("EditVectorComputer")
struct EditVectorTests {
	@Test("Identical text produces all matches")
	func identicalText() {
		let (vector, edits) = EditVectorComputer.compute(original: "hello world", edited: "hello world")
		#expect(vector == "MM")
		#expect(edits.allSatisfy { $0.operation == .match })
	}

	@Test("Single word substitution")
	func singleSubstitution() {
		let (vector, edits) = EditVectorComputer.compute(original: "hello world", edited: "hello planet")
		#expect(vector == "MS")
		#expect(edits[0].operation == .match)
		#expect(edits[1].operation == .substitution)
		#expect(edits[1].original == "world")
		#expect(edits[1].corrected == "planet")
	}

	@Test("Casing-only change detected")
	func casingChange() {
		let (vector, edits) = EditVectorComputer.compute(original: "hello claude", edited: "hello Claude")
		#expect(vector == "MC")
		#expect(edits[1].operation == .casing)
		#expect(edits[1].original == "claude")
		#expect(edits[1].corrected == "Claude")
	}

	@Test("Word insertion detected")
	func insertion() {
		let (vector, edits) = EditVectorComputer.compute(original: "hello world", edited: "hello beautiful world")
		#expect(vector == "MIM")
		#expect(edits[1].operation == .insert)
		#expect(edits[1].corrected == "beautiful")
	}

	@Test("Word deletion detected")
	func deletion() {
		let (vector, edits) = EditVectorComputer.compute(original: "hello beautiful world", edited: "hello world")
		#expect(vector == "MDM")
		#expect(edits[1].operation == .delete)
		#expect(edits[1].original == "beautiful")
	}

	@Test("Empty original text")
	func emptyOriginal() {
		let (vector, edits) = EditVectorComputer.compute(original: "", edited: "hello world")
		#expect(vector == "II")
		#expect(edits.allSatisfy { $0.operation == .insert })
	}

	@Test("Empty edited text")
	func emptyEdited() {
		let (vector, edits) = EditVectorComputer.compute(original: "hello world", edited: "")
		#expect(vector == "DD")
		#expect(edits.allSatisfy { $0.operation == .delete })
	}

	@Test("Both empty")
	func bothEmpty() {
		let (vector, edits) = EditVectorComputer.compute(original: "", edited: "")
		#expect(vector == "")
		#expect(edits.isEmpty)
	}

	@Test("Complex edit: substitution + casing + insertion")
	func complexEdit() {
		let (vector, _) = EditVectorComputer.compute(
			original: "clawed code is great",
			edited: "Claude Code is really great"
		)
		// clawed→Claude (S), code→Code (C), is→is (M), [insert really], great→great (M)
		#expect(vector.contains("S"))
		#expect(vector.contains("C"))
		#expect(vector.contains("M"))
	}

	@Test("WordEdit is Codable")
	func codable() throws {
		let edit = WordEdit(original: "clawed", corrected: "Claude", operation: .substitution)
		let data = try JSONEncoder().encode(edit)
		let decoded = try JSONDecoder().decode(WordEdit.self, from: data)
		#expect(decoded == edit)
	}
}
