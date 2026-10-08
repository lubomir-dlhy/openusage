import XCTest
@testable import OpenUsage

final class ClaudeUsageCreditsTests: XCTestCase {
    private func creditsValue(_ json: String) throws -> MetricValue? {
        let response = HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))
        let mapped = try ClaudeUsageMapper.mapUsageResponse(response, credentials: ClaudeOAuth(subscriptionType: "max"))
        for line in mapped.lines {
            if case .values(let label, let values, _, _, _, _) = line, label == "Usage Credits" { return values.first }
        }
        return nil
    }

    func testDisabledCreditsShowAmountSpentAndOff() throws {
        // Shape from a live Max 20x response with usage credits turned off.
        let value = try XCTUnwrap(creditsValue("""
        { "spend": { "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
                     "limit": null, "enabled": false, "balance": null } }
        """))
        XCTAssertEqual(value.number, 0)
        XCTAssertEqual(value.kind, .dollars)
        XCTAssertEqual(value.label, "used · off")
    }

    func testBalanceWinsOverAmountSpent() throws {
        let value = try XCTUnwrap(creditsValue("""
        { "spend": { "used": { "amount_minor": 250, "exponent": 2 }, "enabled": true,
                     "balance": { "amount_minor": 1234, "exponent": 2 } } }
        """))
        XCTAssertEqual(value.number, 12.34, accuracy: 0.0001)
        XCTAssertEqual(value.label, "balance")
    }

    func testMissingSpendBlockEmitsNoRow() throws {
        XCTAssertNil(try creditsValue("{}"))
    }
}
