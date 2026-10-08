import XCTest
@testable import OpenUsage

final class SubscriptionRenewalTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { OpenUsageISO8601.date(from: text)! }

    func testNextRollsWholeMonthsFromTheOriginalAnchor() {
        let anchor = date("2026-01-31T10:00:00Z")
        XCTAssertEqual(SubscriptionRenewal.next(anchor: anchor, after: date("2026-02-10T00:00:00Z"), calendar: utc),
                       date("2026-02-28T10:00:00Z"))
        XCTAssertEqual(SubscriptionRenewal.next(anchor: anchor, after: date("2026-03-01T00:00:00Z"), calendar: utc),
                       date("2026-03-31T10:00:00Z"))
        XCTAssertEqual(SubscriptionRenewal.next(anchor: anchor, months: 12, after: date("2026-02-01T00:00:00Z"), calendar: utc),
                       date("2027-01-31T10:00:00Z"))
    }

    func testClaudeProjectsFromSubscriptionStartForActiveStripePlans() throws {
        let json = """
        { "account": { "uuid": "a" }, "organization": { "uuid": "o", "organization_type": "claude_max",
          "billing_type": "stripe_subscription", "subscription_status": "active",
          "subscription_created_at": "2026-08-25T16:19:45.326661Z" } }
        """
        let profile = try JSONDecoder().decode(ClaudeAccountProfile.self, from: Data(json.utf8))
        let renewal = try XCTUnwrap(ClaudeUsageMapper.renewal(profile: profile, now: date("2026-10-08T12:00:00Z")))
        XCTAssertTrue(renewal.estimated)
        XCTAssertEqual(utc.dateComponents([.month, .day], from: renewal.date), DateComponents(month: 10, day: 25))

        let inactive = json.replacingOccurrences(of: "\"active\"", with: "\"canceled\"")
        let canceled = try JSONDecoder().decode(ClaudeAccountProfile.self, from: Data(inactive.utf8))
        XCTAssertNil(ClaudeUsageMapper.renewal(profile: canceled, now: date("2026-10-08T12:00:00Z")))
    }

    private func idToken(start: String, until: String) -> String {
        let claims: [String: Any] = ["https://api.openai.com/auth": [
            "chatgpt_subscription_active_start": start, "chatgpt_subscription_active_until": until
        ]]
        let payload = try! JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).sig"
    }

    func testCodexUsesCurrentPeriodEndWhileTheTokenIsFresh() throws {
        let auth = CodexAuth(tokens: CodexTokens(idToken: idToken(start: "2026-09-14T15:27:59+00:00",
                                                                until: "2026-10-14T15:27:59+00:00")))
        let renewal = try XCTUnwrap(CodexUsageMapper.renewal(auth: auth, now: date("2026-10-08T12:00:00Z")))
        XCTAssertEqual(renewal, SubscriptionRenewal(date: date("2026-10-14T15:27:59Z"), estimated: false))
    }

    func testCodexRollsALapsedPeriodForwardAndMarksItEstimated() throws {
        let auth = CodexAuth(tokens: CodexTokens(idToken: idToken(start: "2026-08-04T17:22:11+00:00",
                                                                until: "2026-09-04T17:22:11+00:00")))
        let renewal = try XCTUnwrap(CodexUsageMapper.renewal(auth: auth, now: date("2026-10-08T12:00:00Z")))
        XCTAssertTrue(renewal.estimated)
        XCTAssertEqual(utc.dateComponents([.month, .day], from: renewal.date), DateComponents(month: 11, day: 4))
    }

    func testCodexWithoutSubscriptionClaimsHasNoRenewal() {
        XCTAssertNil(CodexUsageMapper.renewal(auth: CodexAuth(tokens: CodexTokens(idToken: "x.e30.y")),
                                              now: Date()))
    }
}
