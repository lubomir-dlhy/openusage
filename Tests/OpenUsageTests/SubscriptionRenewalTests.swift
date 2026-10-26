import XCTest
@testable import OpenUsage

final class SubscriptionRenewalTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { OpenUsageISO8601.date(from: text)! }

    func testBillingDayIsThisMonthUntilItPasses() {
        XCTAssertEqual(SubscriptionRenewal.next(billingDay: 26, after: date("2026-10-26T18:00:00Z"), calendar: utc),
                       date("2026-10-26T00:00:00Z"))
        XCTAssertEqual(SubscriptionRenewal.next(billingDay: 9, after: date("2026-10-26T18:00:00Z"), calendar: utc),
                       date("2026-11-09T00:00:00Z"))
    }

    func testBillingDayClampsToShortMonths() {
        XCTAssertEqual(SubscriptionRenewal.next(billingDay: 31, after: date("2026-02-10T00:00:00Z"), calendar: utc),
                       date("2026-02-28T00:00:00Z"))
        XCTAssertEqual(SubscriptionRenewal.next(billingDay: 31, after: date("2026-03-01T00:00:00Z"), calendar: utc),
                       date("2026-03-31T00:00:00Z"))
        XCTAssertNil(SubscriptionRenewal.next(billingDay: 0, after: date("2026-03-01T00:00:00Z"), calendar: utc))
    }

    private func accountCheck(
        planType: String = "promax",
        entitlement: [String: Any],
        willRenew: Bool? = true
    ) -> HTTPResponse {
        var account: [String: Any] = [
            "account": ["plan_type": planType],
            "entitlement": ["has_active_subscription": true].merging(entitlement) { $1 }
        ]
        if let willRenew { account["last_active_subscription"] = ["will_renew": willRenew] }
        let body = try! JSONSerialization.data(withJSONObject: ["accounts": ["acct-1": account, "default": account]])
        return HTTPResponse(statusCode: 200, headers: [:], body: body)
    }

    // Regression: the stale login-token claim put a Pro 500 renewal on 4 Nov; the account reports 12 Nov.
    func testCodexRenewsOnTheReportedDate() {
        let response = accountCheck(entitlement: [
            "renews_at": "2026-11-12T12:31:45+00:00", "expires_at": "2026-11-12T18:31:45+00:00", "cancels_at": NSNull()
        ])
        XCTAssertEqual(CodexUsageMapper.renewal(accountCheck: response, accountID: "acct-1"),
                       SubscriptionRenewal(date: date("2026-11-12T12:31:45Z"), status: .renews))
    }

    func testCodexCancelledSubscriptionEnds() {
        let response = accountCheck(
            planType: "prolite",
            entitlement: ["renews_at": "2026-11-14T15:27:59+00:00", "cancels_at": NSNull()],
            willRenew: false
        )
        XCTAssertEqual(CodexUsageMapper.renewal(accountCheck: response, accountID: "acct-1"),
                       SubscriptionRenewal(date: date("2026-11-14T15:27:59Z"), status: .ends))
    }

    func testCodexScheduledPlanChangeReportsDirection() {
        let downgrade = accountCheck(entitlement: [
            "renews_at": "2026-11-12T12:31:45+00:00",
            "scheduled_plan_change": ["plan_type": "plus", "changes_at": "2026-11-12T12:31:45+00:00"]
        ])
        XCTAssertEqual(CodexUsageMapper.renewal(accountCheck: downgrade, accountID: nil),
                       SubscriptionRenewal(date: date("2026-11-12T12:31:45Z"), status: .downgrades, newPlan: "Plus"))

        let upgrade = accountCheck(planType: "prolite", entitlement: [
            "scheduled_plan_change": ["plan_type": "promax", "changes_at": "2026-11-14T15:27:59+00:00"]
        ])
        XCTAssertEqual(CodexUsageMapper.renewal(accountCheck: upgrade, accountID: "acct-1")?.status, .upgrades)

        let unranked = accountCheck(entitlement: [
            "scheduled_plan_change": ["plan_type": "team", "changes_at": "2026-11-14T15:27:59+00:00"]
        ])
        XCTAssertEqual(CodexUsageMapper.renewal(accountCheck: unranked, accountID: "acct-1")?.status, .changes)
    }

    func testCodexWithoutActiveSubscriptionHasNoRenewal() {
        let free = accountCheck(planType: "free", entitlement: ["has_active_subscription": false])
        XCTAssertNil(CodexUsageMapper.renewal(accountCheck: free, accountID: "acct-1"))
        XCTAssertNil(CodexUsageMapper.renewal(accountCheck: HTTPResponse(statusCode: 403, headers: [:], body: Data()),
                                              accountID: "acct-1"))
    }
}
