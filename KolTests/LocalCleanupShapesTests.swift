import Testing
@testable import KolCore

struct LocalCleanupShapesTests {
    @Test func prefillRoundsUpToFixedLengths() {
        #expect(LocalCleanupShapes.paddedLength(count: 1, position: 0, capacity: 1024) == 64)
        #expect(LocalCleanupShapes.paddedLength(count: 64, position: 0, capacity: 1024) == 64)
        #expect(LocalCleanupShapes.paddedLength(count: 65, position: 0, capacity: 1024) == 96)
        #expect(LocalCleanupShapes.paddedLength(count: 341, position: 0, capacity: 1024) == 384)
        #expect(LocalCleanupShapes.paddedLength(count: 690, position: 0, capacity: 1024) == 768)
        #expect(LocalCleanupShapes.paddedLength(count: 769, position: 0, capacity: 1024) == 1024)
        #expect(LocalCleanupShapes.paddedLength(count: 1023, position: 0, capacity: 1024) == 1024)
    }

    @Test func stepsRoundUpToFixedLengths() {
        #expect(LocalCleanupShapes.paddedLength(count: 1, position: 300, capacity: 1024) == 1)
        #expect(LocalCleanupShapes.paddedLength(count: 2, position: 300, capacity: 1024) == 9)
        #expect(LocalCleanupShapes.paddedLength(count: 17, position: 300, capacity: 1024) == 17)
        #expect(LocalCleanupShapes.paddedLength(count: 33, position: 300, capacity: 1024) == 33)
    }

    @Test func neverPadsPastTheCache() {
        // Five slots remain, so a two-token step uses all five instead of nine.
        #expect(LocalCleanupShapes.paddedLength(count: 2, position: 1019, capacity: 1024) == 5)
        #expect(LocalCleanupShapes.paddedLength(count: 1, position: 1023, capacity: 1024) == 1)
    }

    @Test func distinctLengthsStayBounded() {
        var lengths = Set<Int>()
        for count in 1..<1024 { lengths.insert(LocalCleanupShapes.paddedLength(count: count, position: 0, capacity: 1024)) }
        for count in 1...33 { lengths.insert(LocalCleanupShapes.paddedLength(count: count, position: 100, capacity: 1024)) }
        #expect(lengths.count == LocalCleanupShapes.prefillLengths.count + LocalCleanupShapes.stepLengths.count)
    }
}
