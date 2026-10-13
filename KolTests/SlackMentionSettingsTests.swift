import Foundation
import Testing
@testable import KolCore

struct SlackMentionSettingsTests {
    @Test func missingPreferenceStaysOffWithoutChangingExplicitMentions() throws {
        let settings = try JSONDecoder().decode(KolSettings.self, from: Data(#"{"atMentionInsertionEnabled":true}"#.utf8))
        #expect(!settings.slackDirectMentionsEnabled)
        #expect(settings.atMentionInsertionEnabled)
    }

    @Test(arguments: [false, true])
    func preferenceSurvivesRoundTrip(_ enabled: Bool) throws {
        let settings = KolSettings(slackDirectMentionsEnabled: enabled)
        let decoded = try JSONDecoder().decode(KolSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.slackDirectMentionsEnabled == enabled)
        #expect(decoded == settings)
    }
}
