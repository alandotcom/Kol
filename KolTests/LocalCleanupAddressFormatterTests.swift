import Testing
@testable import KolCore

struct LocalCleanupAddressFormatterTests {
    @Test func writesDictatedAddressesAsTyped() {
        #expect(LocalCleanupAddressFormatter.apply("Tessix dot com.") == "tessix.com")
        #expect(LocalCleanupAddressFormatter.apply("Zentiva.dot.Dev.") == "zentiva.dev")
        #expect(LocalCleanupAddressFormatter.apply("Vaultly.io.") == "vaultly.io")
    }

    @Test func keepsSentencesAroundAddresses() {
        #expect(LocalCleanupAddressFormatter.apply("Open Vaultly.com please.") == "Open vaultly.com please.")
        #expect(LocalCleanupAddressFormatter.apply("That was the dot com era.") == "That was the dot com era.")
        #expect(LocalCleanupAddressFormatter.apply("Nothing to change here.") == "Nothing to change here.")
    }
}
