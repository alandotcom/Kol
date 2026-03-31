import Testing

@testable import KolCore

@Suite("NameParser metadata parsing")
struct WindowContextMetadataTests {

	// MARK: - parseNamesFromDescription

	@Test("Parses two names from Slack member button")
	func twoNames() {
		let desc = "View all 3 members. Includes Joe Cho and Sean Cotter"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Joe Cho", "Sean Cotter"])
	}

	@Test("Parses multiple names with Oxford comma")
	func multipleNamesOxford() {
		let desc = "View all 5 members. Includes Alice, Bob, Charlie, Dan, and Eve"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Alice", "Bob", "Charlie", "Dan", "Eve"])
	}

	@Test("Parses multiple names without Oxford comma")
	func multipleNamesNoOxford() {
		let desc = "View all 3 members. Includes Alice, Bob and Charlie"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Alice", "Bob", "Charlie"])
	}

	@Test("Parses simple two-name pattern without preamble")
	func simpleIncludes() {
		let desc = "Includes Alice and Bob"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Alice", "Bob"])
	}

	@Test("Returns empty for no Includes keyword")
	func noIncludesKeyword() {
		let desc = "View all 3 members."
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names.isEmpty)
	}

	@Test("Returns empty for empty string")
	func emptyString() {
		let names = NameParser.parseNamesFromDescription("")
		#expect(names.isEmpty)
	}

	@Test("Handles trailing period")
	func trailingPeriod() {
		let desc = "Includes Alan Cohen and Sarah Smith."
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Alan Cohen", "Sarah Smith"])
	}

	@Test("Filters out non-name strings")
	func filtersNonNames() {
		let desc = "Includes valid Name and some random lowercase"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(!names.contains("some random lowercase"))
	}

	@Test("Handles Unicode names")
	func unicodeNames() {
		let desc = "Includes Ren and Lian"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Ren", "Lian"])
	}

	@Test("Handles hyphenated names")
	func hyphenatedNames() {
		let desc = "Includes Mary-Jane Watson and Peter Parker"
		let names = NameParser.parseNamesFromDescription(desc)
		#expect(names == ["Mary-Jane Watson", "Peter Parker"])
	}

	// MARK: - looksLikePersonName

	@Test("Accepts valid person names")
	func validNames() {
		#expect(NameParser.looksLikePersonName("Alice"))
		#expect(NameParser.looksLikePersonName("Alan Cohen"))
		#expect(NameParser.looksLikePersonName("Mary-Jane"))
		#expect(NameParser.looksLikePersonName("Sean O'Brien"))
	}

	@Test("Rejects non-names")
	func invalidNames() {
		#expect(!NameParser.looksLikePersonName(""))
		#expect(!NameParser.looksLikePersonName("a"))
		#expect(!NameParser.looksLikePersonName("hello world"))
		#expect(!NameParser.looksLikePersonName("View all 3 members"))
		#expect(!NameParser.looksLikePersonName("12345"))
	}
}
