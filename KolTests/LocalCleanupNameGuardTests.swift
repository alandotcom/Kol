import Testing
@testable import KolCore

struct LocalCleanupNameGuardTests {
    private let names = ["Mirelle Ostby", "Hasnack Alumni Night", "Kol", "TideWire", "Yuki Tanaka"]

    @Test func acceptsNamesThatSoundLikeTheSpeech() {
        #expect(LocalCleanupNameGuard.accepts(transcript: "has neck alumni", cleaned: "Hasnack Alumni.", names: names))
        #expect(LocalCleanupNameGuard.accepts(transcript: "let's see if it works with coal", cleaned: "Let's see if it works with Kol.", names: names))
        #expect(LocalCleanupNameGuard.accepts(transcript: "ok tide wire sounds good", cleaned: "OK, TideWire, sounds good.", names: names))
        #expect(LocalCleanupNameGuard.accepts(transcript: "thanks yuki tanacka", cleaned: "Thanks, Yuki Tanaka.", names: names))
    }

    @Test func rejectsNamesThatDoNotSoundLikeTheSpeech() {
        #expect(!LocalCleanupNameGuard.accepts(transcript: "has neck alumni", cleaned: "Has Mirelle Ostby.", names: names))
        #expect(!LocalCleanupNameGuard.accepts(transcript: "see you tomorrow", cleaned: "See you tomorrow, Yuki.", names: names))
    }

    @Test func ignoresChangesThatIntroduceNoName() {
        #expect(LocalCleanupNameGuard.accepts(transcript: "um so i think we should go", cleaned: "I think we should go.", names: names))
        #expect(LocalCleanupNameGuard.accepts(transcript: "ask mirelle ostby", cleaned: "Ask Mirelle Ostby.", names: names))
        #expect(LocalCleanupNameGuard.accepts(transcript: "anything", cleaned: "Anything.", names: []))
    }

    @Test func skeletonMergesSpellingVariants() {
        #expect(LocalCleanupNameGuard.skeleton("Brenscher") == LocalCleanupNameGuard.skeleton("brensher"))
        #expect(LocalCleanupNameGuard.skeleton("coal") == LocalCleanupNameGuard.skeleton("Kol"))
    }

    @Test func checksNamesFromCustomRules() {
        let rules = "My name is Yuki Tanaka and I work at Example Labs."
        #expect(!LocalCleanupNameGuard.accepts(transcript: "why do you keep using fable for this", cleaned: "Why do you keep using Example Labs for this?", names: [rules]))
        #expect(LocalCleanupNameGuard.accepts(transcript: "I work at example labs", cleaned: "I work at Example Labs.", names: [rules]))
    }
}
