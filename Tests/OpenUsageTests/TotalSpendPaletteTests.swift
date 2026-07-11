import SwiftUI
import XCTest
@testable import OpenUsage

/// Covers the Total Spend tint resolution: a user-assigned account color overrides the brand /
/// fallback tints, and malformed stored values fall back rather than rendering a wrong color.
final class TotalSpendPaletteTests: XCTestCase {
    func testAccountTintOverridesAutomaticColor() {
        let plain = Provider(id: "claude#1", displayName: "Claude · Work", icon: .providerMark("claude"))
        let tinted = Provider(id: "claude#1", displayName: "Claude · Work", icon: .providerMark("claude"), tintHex: "0A84FF")

        XCTAssertEqual(TotalSpendPalette.color(for: plain), TotalSpendPalette.color(for: "claude#1"),
                       "no tint → the automatic (hash-fallback) color")
        XCTAssertEqual(TotalSpendPalette.color(for: tinted), TotalSpendPalette.parseHex("0A84FF"),
                       "assigned tint wins over the automatic color")
    }

    func testParseHexAcceptsPrefixedAndRejectsMalformed() {
        XCTAssertNotNil(TotalSpendPalette.parseHex("DE7356"))
        XCTAssertEqual(TotalSpendPalette.parseHex("#DE7356"), TotalSpendPalette.parseHex("DE7356"))
        XCTAssertNil(TotalSpendPalette.parseHex("nope"))
        XCTAssertNil(TotalSpendPalette.parseHex("FFF"))
        XCTAssertNil(TotalSpendPalette.parseHex(""))
    }

    func testMalformedStoredTintFallsBackToAutomatic() {
        let broken = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"), tintHex: "not-a-color")
        XCTAssertEqual(TotalSpendPalette.color(for: broken), TotalSpendPalette.color(for: "codex"),
                       "a malformed stored value falls back to the brand color")
    }

    func testAccountColorRoundTripsThroughCoding() throws {
        var account = ProviderAccount.makeDefault(providerID: "claude")
        account.colorHex = "34C759"
        let decoded = try JSONDecoder().decode(ProviderAccount.self, from: JSONEncoder().encode(account))
        XCTAssertEqual(decoded.colorHex, "34C759")

        // Pre-color persisted accounts (no colorHex key) keep decoding — the field is optional.
        let legacy = Data(#"{"id":"claude#1","providerID":"claude","label":"Work"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ProviderAccount.self, from: legacy).colorHex)
    }
}
