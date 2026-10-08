import XCTest
@testable import OpenUsage

final class AccountTableTests: XCTestCase {
    private func meter(_ title: String, _ used: Double) -> WidgetData {
        WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: used, limit: 100)
    }

    private func entry(_ id: String, _ data: WidgetData, always: Bool = true) -> AccountTable.Entry {
        AccountTable.Entry(id: id, data: data, alwaysShown: always)
    }

    func testFamilyCoversDiscoveredAndConfiguredAccounts() {
        XCTAssertEqual(AccountTable.family(of: "claude"), "claude")
        XCTAssertEqual(AccountTable.family(of: "claude@31af89c4"), "claude")
        XCTAssertEqual(AccountTable.family(of: "claude#1"), "claude")
        XCTAssertEqual(AccountTable.family(of: "codex@44de9546"), "codex")
    }

    func testColumnsAreTheUnionOfAlwaysVisibleLimitsCappedAtThree() {
        var trend = WidgetData(title: "Usage Trend", icon: .providerMark("claude"), kind: .count, used: 0)
        trend.isChart = true
        let first = [entry("a.session", meter("Session", 1)), entry("a.weekly", meter("Weekly", 2)), entry("a.trend", trend)]
        let second = [entry("b.weekly", meter("Weekly", 3)), entry("b.fable", meter("Fable", 4)),
                      entry("b.sonnet", meter("Sonnet", 5)), entry("b.spark", meter("Spark", 6), always: false)]
        XCTAssertEqual(AccountTable.columns([first, second]), ["Session", "Weekly", "Fable"])
    }

    func testRowWithoutDataIsNotAColumn() {
        var empty = meter("Extra Usage", 0)
        empty.hasData = false
        XCTAssertEqual(AccountTable.columns([[entry("a.extra", empty), entry("a.weekly", meter("Weekly", 1))]]), ["Weekly"])
    }

    func testResetsCarryCountAndSortedExpiries() {
        var resets = WidgetData(title: "Rate Limit Resets", icon: .providerMark("codex"), kind: .count, used: 0)
        resets.showsResetExpiries = true
        resets.values = [MetricValue(number: 2, kind: .count, label: "available")]
        let late = Date(timeIntervalSince1970: 2_000), early = Date(timeIntervalSince1970: 1_000)
        resets.expiriesAt = [late, early]
        let found = AccountTable.resets(in: [entry("c.rateLimitResets", resets, always: false)])
        XCTAssertEqual(found, AccountTable.Resets(count: 2, expiries: [early, late]))
        XCTAssertEqual(found?.soonest, early)

        resets.values = [MetricValue(number: 0, kind: .count, label: "available")]
        XCTAssertNil(AccountTable.resets(in: [entry("c.rateLimitResets", resets)]))
    }

    func testRowNamePrefersRenameThenOrganizationThenEmail() {
        XCTAssertEqual(AccountTable.rowName(displayName: "Claude — CulturePulse", recordLabel: "x@y.z (CulturePulse)",
                                            customLabel: "Work", familyName: "Claude"), "Work")
        XCTAssertEqual(AccountTable.rowName(displayName: "Claude — CulturePulse", recordLabel: "ldlhy@culturepulse.ai (CulturePulse)",
                                            customLabel: nil, familyName: "Claude"), "CulturePulse")
        XCTAssertEqual(AccountTable.rowName(displayName: "Claude — contact@lubomirdlhy.sk's Organization",
                                            recordLabel: "contact@lubomirdlhy.sk (contact@lubomirdlhy.sk's Organization)",
                                            customLabel: nil, familyName: "Claude"), "contact@lubomirdlhy.sk")
        XCTAssertEqual(AccountTable.rowName(displayName: "Claude · CulturePulse", recordLabel: nil,
                                            customLabel: nil, familyName: "Claude"), "CulturePulse")
        XCTAssertEqual(AccountTable.rowName(displayName: "Codex", recordLabel: nil, customLabel: nil, familyName: "Codex"), "Default")
    }

    func testExpiryCountdownDropsHoursFromAWeekOut() {
        XCTAssertEqual(Formatters.expiryCountdown(14 * 86_400 + 2 * 3_600), "14d")
        XCTAssertEqual(Formatters.expiryCountdown(3 * 86_400 + 5 * 3_600), "3d 5h")
        XCTAssertEqual(Formatters.expiryCountdown(5 * 3_600 + 20 * 60), "5h 20m")
        XCTAssertNil(Formatters.expiryCountdown(-1))
    }
}
