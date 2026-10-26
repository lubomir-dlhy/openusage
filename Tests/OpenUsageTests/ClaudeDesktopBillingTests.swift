import CryptoKit
import XCTest
@testable import OpenUsage

final class ClaudeDesktopBillingTests: XCTestCase {
    private func details(_ fields: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["status": "active", "billing_interval": "monthly"].merging(fields) { $1 })
    }

    private func date(_ text: String) -> Date { OpenUsageISO8601.date(from: text)! }

    // Regression: projecting from subscription_created_at put this Max 20x renewal on 5 Nov; claude.ai says 26 Nov.
    func testRenewsOnTheNextCharge() {
        let body = details(["next_charge_at": "2026-11-26T08:03:05Z", "next_charge_date": "2026-11-26"])
        XCTAssertEqual(ClaudeDesktopBilling.renewal(subscriptionDetails: body),
                       SubscriptionRenewal(date: date("2026-11-26T08:03:05Z"), status: .renews))
    }

    func testLegacyChargeDateStaysOnItsCalendarDay() {
        let body = details(["next_charge_date": "2026-11-13"])
        XCTAssertEqual(ClaudeDesktopBilling.renewal(subscriptionDetails: body)?.date, date("2026-11-13T12:00:00Z"))
    }

    func testCancelledPlanEnds() {
        let body = details(["next_charge_at": NSNull(), "plan_ending_at": "2026-11-09T10:00:00Z"])
        XCTAssertEqual(ClaudeDesktopBilling.renewal(subscriptionDetails: body),
                       SubscriptionRenewal(date: date("2026-11-09T10:00:00Z"), status: .ends))
    }

    func testScheduledDowngradeNamesThePlan() {
        let body = details([
            "next_charge_at": "2026-11-26T08:03:05Z",
            "scheduled_downgrade": ["plan_type": "max_5x_monthly", "date": "2026-11-26T08:03:05Z"]
        ])
        XCTAssertEqual(ClaudeDesktopBilling.renewal(subscriptionDetails: body),
                       SubscriptionRenewal(date: date("2026-11-26T08:03:05Z"), status: .downgrades, newPlan: "Max 5x"))
        XCTAssertEqual(ClaudeDesktopBilling.planName("pro_annual"), "Pro")
    }

    func testInactiveSubscriptionHasNoRenewal() {
        XCTAssertNil(ClaudeDesktopBilling.renewal(subscriptionDetails: details(["status": "canceled"])))
        XCTAssertNil(ClaudeDesktopBilling.renewal(subscriptionDetails: Data("{}".utf8)))
    }

    func testTriesEachSessionUntilOneSeesTheOrganization() async throws {
        let http = RoutingHTTPClient { request in
            let cookie = request.headers["Cookie"] ?? ""
            guard cookie == "sessionKey=sk-ant-work" else {
                return HTTPResponse(statusCode: 403, headers: [:], body: Data())
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"status":"active","next_charge_at":"2026-11-13T11:33:05Z"}"#.utf8))
        }
        let home = try sessionHome(["Claude": "sk-ant-personal", "Parall/Claude (Work)": "sk-ant-work"])
        let billing = ClaudeDesktopBilling(sessions: home, http: http)

        let renewal = await billing.renewal(organization: "F75AA8F6-59D4-462F-848D-D1E1BF305E9D")
        XCTAssertEqual(renewal, SubscriptionRenewal(date: date("2026-11-13T11:33:05Z"), status: .renews))
        XCTAssertEqual(http.requests.map(\.url.path),
                       Array(repeating: "/api/organizations/f75aa8f6-59d4-462f-848d-d1e1bf305e9d/subscription_details", count: 2))

        _ = await billing.renewal(organization: "f75aa8f6-59d4-462f-848d-d1e1bf305e9d")
        XCTAssertEqual(http.requests.count, 2, "a second card for the same organization reuses the result")
    }

    /// A temp home with one encrypted `sessionKey` cookie per profile directory.
    private func sessionHome(_ profiles: [String: String]) throws -> ClaudeDesktopSessionReader {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let key = try ClaudeDesktopAuthStore.deriveKey(password: "secret")
        var cookies: [String: String] = [:]
        for (profile, session) in profiles {
            let directory = home.appendingPathComponent("Library/Application Support/\(profile)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = directory.appendingPathComponent("Cookies")
            try Data().write(to: database)
            let plaintext = Data(SHA256.hash(data: Data(".claude.ai".utf8))) + Data(session.utf8)
            cookies[database.path] = try ClaudeDesktopAuthStoreTests().encrypt(plaintext, key: key)
                .map { String(format: "%02X", $0) }.joined()
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return ClaudeDesktopSessionReader(
            sqlite: PathSQLite(values: cookies),
            keyReader: FakeClaudeDesktopKeyReader(password: "secret", requiresInteraction: false),
            homeDirectory: { home }
        )
    }
}

private final class PathSQLite: SQLiteAccessing, @unchecked Sendable {
    let values: [String: String]
    init(values: [String: String]) { self.values = values }
    func queryValue(path: String, sql: String) throws -> String? { values[path] }
    func execute(path: String, sql: String) throws {}
}
