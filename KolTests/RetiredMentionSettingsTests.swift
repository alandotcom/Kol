import Foundation
import Testing
@testable import KolCore

struct RetiredMentionSettingsTests {
    @Test("Retired automatic mention preference is ignored without resetting settings", arguments: [true, false])
    func ignoresRetiredPreference(_ enabled: Bool) throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "slackDirectMentionsEnabled": enabled,
            "atMentionInsertionEnabled": true,
            "conversationContextEnabled": true,
            "llmScreenContextEnabled": true,
            "llmCustomRules": "Use concise punctuation.",
            "showDockIcon": false
        ])
        let settings = try JSONDecoder().decode(KolSettings.self, from: payload)
        #expect(settings.atMentionInsertionEnabled)
        #expect(settings.conversationContextEnabled)
        #expect(settings.llmScreenContextEnabled)
        #expect(settings.llmCustomRules == "Use concise punctuation.")
        #expect(!settings.showDockIcon)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        #expect(encoded["slackDirectMentionsEnabled"] == nil)
    }
}
