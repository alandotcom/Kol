import Testing
@testable import KolCore

struct LocalCleanupDraftTests {
    @Test func continuesAfterUniqueMatch() {
        let draft = [10, 11, 12, 13, 14]
        #expect(LocalCleanupDraft.nextCursor(draft: draft, output: [7, 11, 12], cursor: 0) == 3)
    }

    @Test func prefersRepeatNearestThePreviousPosition() {
        // The phrase 1 2 3 appears at index 0 and again at index 10. After copying up to index 13,
        // the output ends with 1 2 3, and the second occurrence is the one being copied.
        let draft = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5]
        #expect(LocalCleanupDraft.nextCursor(draft: draft, output: [1, 2, 3], cursor: 13) == 13)
    }

    @Test func prefersLongerSuffixOverNearerShortMatch() {
        // Only the occurrence at index 4 matches all of 5 6 7.
        let draft = [7, 0, 0, 0, 5, 6, 7, 9]
        #expect(LocalCleanupDraft.nextCursor(draft: draft, output: [5, 6, 7], cursor: 1) == 7)
    }

    @Test func returnsNilWithoutMatch() {
        #expect(LocalCleanupDraft.nextCursor(draft: [1, 2, 3], output: [9], cursor: 0) == nil)
        #expect(LocalCleanupDraft.nextCursor(draft: [], output: [1], cursor: 0) == nil)
    }

    @Test func ignoresMatchesBeforeTheLookbackWindow() {
        let draft = [42] + Array(repeating: 0, count: 100)
        #expect(LocalCleanupDraft.nextCursor(draft: draft, output: [42], cursor: 100) == nil)
    }
}
