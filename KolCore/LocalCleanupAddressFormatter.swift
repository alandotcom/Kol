import Foundation

/// Writes dictated web addresses the way they are typed.
///
/// Speech recognition and the cleanup model leave addresses in sentence form: "tessix dot com",
/// "Zentiva.dot.dev", "Vaultly.com." This formatter joins a spoken "dot" before a common ending,
/// writes addresses in lowercase, and drops the sentence period when the dictation is only an
/// address (typed into an address bar or search field).
public enum LocalCleanupAddressFormatter {
    static let endings = "com|io|dev|app|org|net|co|ai|me|so|xyz|edu|gov"
    /// Words that end a phrase like "the dot com era" rather than name a site.
    static let notSiteNames: Set<String> = ["the", "a", "an", "of", "in", "on", "at", "to", "for", "with", "and", "or", "that", "this"]

    public static func apply(_ text: String) -> String {
        var result = text
        // "zentiva dot dev" and "Zentiva.dot.dev" become "zentiva.dev".
        let spoken = try! NSRegularExpression(pattern: #"\b([A-Za-z0-9-]+)(?:\s+dot\s+|\.dot\.)(\#(endings))\b"#, options: [.caseInsensitive])
        for match in spoken.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result), let site = Range(match.range(at: 1), in: result),
                  let ending = Range(match.range(at: 2), in: result),
                  !notSiteNames.contains(result[site].lowercased()) else { continue }
            result.replaceSubrange(whole, with: "\(result[site]).\(result[ending])")
        }
        // Addresses are lowercase: "Vaultly.com" becomes "vaultly.com".
        let address = try! NSRegularExpression(pattern: #"\b[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:\#(endings))\b"#, options: [.caseInsensitive])
        for match in address.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: result[range].lowercased())
        }
        // A dictation that is only an address keeps no sentence period.
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("."), address.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)).map({ $0.range.length == (trimmed as NSString).length - 1 }) == true {
            result = String(trimmed.dropLast())
        }
        return result
    }
}
