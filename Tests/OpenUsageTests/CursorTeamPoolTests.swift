import XCTest
@testable import OpenUsage

final class CursorTeamPoolTests: XCTestCase {
    func testReportedStandardSeatUsesStructuredTotalInsteadOfLegacyTwentyDollars() throws {
        let mapped = try map([
            "totalSpend": 1022, "includedSpend": 1022, "remaining": 978, "limit": 2000,
            "autoPercentUsed": 2.6476190476190475, "apiPercentUsed": 11.65, "totalPercentUsed": 4.088
        ])
        assertPercent(mapped, "Total usage", 4.088)
        assertPercent(mapped, "Cursor Models", 2.6476190476190475)
        assertPercent(mapped, "Other Models", 11.65)
    }

    func testPremiumSeatWithoutTotalDoesNotInventDollarOrPercentageTotal() throws {
        let mapped = try map([
            "limit": 2000, "totalSpend": 666,
            "autoPercentUsed": 0.3728571428571429, "apiPercentUsed": 2.025
        ])
        XCTAssertNil(mapped.lines.first { $0.label == "Total usage" })
        assertPercent(mapped, "Cursor Models", 0.3728571428571429)
        assertPercent(mapped, "Other Models", 2.025)
    }

    func testPoolsWithoutLimitDoNotTriggerRequestFallback() throws {
        let usage: [String: Any] = [
            "enabled": true,
            "planUsage": ["autoPercentUsed": 0, "apiPercentUsed": 0],
            "spendLimitUsage": ["limitType": "team"]
        ]
        for name: String? in ["Team", "Enterprise", nil] {
            XCTAssertFalse(CursorUsageMapper.shouldUseRequestBasedFallback(
                usage: usage, planName: name, planInfoUnavailable: name == nil
            ).shouldFallback)
        }
        XCTAssertFalse(CursorPlanUsageFacts(usage: usage).shouldTryGenericRequestFallback)
        let mapped = try CursorUsageMapper.mapUsage(
            usage: usage, planName: nil, creditGrants: nil, stripeBalanceCents: 0
        )
        assertPercent(mapped, "Cursor Models", 0)
        assertPercent(mapped, "Other Models", 0)
    }

    func testLegacyFiveThousandDollarPoolWithZeroPlaceholdersKeepsDollarMeter() throws {
        let mapped = try map([
            "limit": 500_000, "totalSpend": 234_500,
            "autoPercentUsed": 0, "apiPercentUsed": 0, "totalPercentUsed": 0
        ])
        guard case .progress(_, let used, let limit, let format, _, _, _) =
            mapped.lines.first(where: { $0.label == "Total usage" }) else {
            return XCTFail("Missing legacy total")
        }
        XCTAssertEqual(used, 2345)
        XCTAssertEqual(limit, 5000)
        XCTAssertEqual(format, .dollars)
    }

    func testIncompleteOrMalformedPoolsKeepLegacyFallback() throws {
        for pools: [String: Any] in [
            ["autoPercentUsed": 1],
            ["autoPercentUsed": true, "apiPercentUsed": 2],
            ["autoPercentUsed": -1, "apiPercentUsed": 2],
            ["autoPercentUsed": Double.infinity, "apiPercentUsed": 2]
        ] {
            let plan = pools.merging(["limit": 500_000, "totalSpend": 234_500]) { first, _ in first }
            let mapped = try map(plan)
            guard case .progress(_, _, _, let format, _, _, _) =
                mapped.lines.first(where: { $0.label == "Total usage" }) else {
                return XCTFail("Missing legacy total")
            }
            XCTAssertEqual(format, .dollars)
        }
    }

    func testTeamNameAloneRecognizesPoolsAndPreservesExtraUsageAndCredits() throws {
        let mapped = try CursorUsageMapper.mapUsage(
            usage: [
                "enabled": true,
                "planUsage": ["limit": 2000, "autoPercentUsed": 0, "apiPercentUsed": 12],
                "spendLimitUsage": ["individualLimit": 5000, "individualRemaining": 4000]
            ],
            planName: " Team ", creditGrants: nil, stripeBalanceCents: 1000
        )
        XCTAssertNil(mapped.lines.first { $0.label == "Total usage" })
        XCTAssertNotNil(mapped.lines.first { $0.label == "On-demand" })
        XCTAssertNotNil(mapped.lines.first { $0.label == "Credits" })
    }

    private func map(_ plan: [String: Any]) throws -> CursorMappedUsage {
        try CursorUsageMapper.mapUsage(
            usage: [
                "enabled": true, "planUsage": plan,
                "billingCycleStart": 1_770_000_000_000, "billingCycleEnd": 1_772_592_000_000,
                "spendLimitUsage": ["limitType": "team", "pooledUsed": 0]
            ],
            planName: "Team", creditGrants: nil, stripeBalanceCents: 0
        )
    }

    func testExtraUsageReadsItsSpendFromTheSameBudgetAsItsLimit() throws {
        func onDemand(_ spend: [String: Any]) throws -> (used: Double, limit: Double) {
            let mapped = try CursorUsageMapper.mapUsage(
                usage: ["enabled": true, "planUsage": ["totalPercentUsed": 10], "spendLimitUsage": spend],
                planName: "Team", creditGrants: nil, stripeBalanceCents: 0
            )
            guard case .progress(_, let used, let limit, _, _, _, _) = mapped.lines.first(where: { $0.label == "On-demand" }) else {
                throw NSError(domain: "no On-demand row", code: 0)
            }
            return (used, limit)
        }

        let personal = try onDemand([
            "individualLimit": 10000, "individualUsed": 0, "individualRemaining": 10000,
            "pooledLimit": 50000, "pooledUsed": 12000, "pooledRemaining": 38000, "totalSpend": 12000, "limitType": "user"
        ])
        XCTAssertEqual(personal.used, 0, "the member spent nothing of their own cap, whatever the team pool spent")
        XCTAssertEqual(personal.limit, 100)

        let pool = try onDemand([
            "pooledLimit": 50000, "pooledUsed": 12000, "pooledRemaining": 38000, "individualUsed": 3400, "limitType": "team"
        ])
        XCTAssertEqual(pool.used, 120, "the pool's spend, not one member's")
        XCTAssertEqual(pool.limit, 500)

        let inferred = try onDemand(["individualLimit": 10000, "individualRemaining": 7500, "pooledUsed": 12000, "totalSpend": 12000])
        XCTAssertEqual(inferred.used, 25, "spend falls back to the same budget's limit minus what's left")

        let ownTotal = try onDemand(["individualLimit": 5000, "individualUsed": 0, "individualRemaining": 4500, "totalSpend": 1200])
        XCTAssertEqual(ownTotal.used, 12, "a personal cap with no team pool still takes totalSpend when individualUsed reads 0")
    }

    func testUnifiedAccountShowsDashboardCreditsAndAdditionalUsage() throws {
        let usage: [String: Any] = [
            "enabled": true,
            "planUsage": ["totalPercentUsed": 42, "autoPercentUsed": 10, "apiPercentUsed": 5],
            "spendLimitUsage": ["individualLimit": 10000, "individualUsed": 500]
        ]
        let mapped = try CursorUsageMapper.mapUsage(
            usage: usage, planName: "Pro", creditGrants: nil, stripeBalanceCents: 0,
            unified: CursorUnifiedBilling(
                creditBalance: ["usdRemainingCents": 1250],
                usageStatus: ["monthlyUsage": [
                    "usedCents": 300, "limitCents": 2000,
                    "periodStart": "2026-11-01T00:00:00Z", "resetsAt": "2026-12-01T00:00:00Z"
                ]]
            )
        )
        XCTAssertEqual(mapped.lines.map(\.label), ["Credits", "Total usage", "On-demand"])
        XCTAssertEqual(mapped.lines.first, .values(label: "Credits", values: [MetricValue(number: 12.5, kind: .dollars)]))
        guard case .progress(_, let used, let limit, _, let resetsAt, let periodMs, _) = mapped.lines.last else {
            return XCTFail("expected an On-demand bar")
        }
        XCTAssertEqual(used, 3)
        XCTAssertEqual(limit, 20)
        XCTAssertEqual(resetsAt, OpenUsageISO8601.date(from: "2026-12-01T00:00:00Z"))
        XCTAssertEqual(periodMs, 30 * 24 * 60 * 60 * 1000)

        let off = try CursorUsageMapper.mapUsage(
            usage: usage, planName: "Pro", creditGrants: nil, stripeBalanceCents: 0,
            unified: CursorUnifiedBilling(creditBalance: nil, usageStatus: ["monthlyUsage": ["usedCents": 0, "additionalUsageOff": true]])
        )
        XCTAssertEqual(off.lines.map(\.label), ["Total usage"])

        let uncapped = try CursorUsageMapper.mapUsage(
            usage: usage, planName: "Pro", creditGrants: nil, stripeBalanceCents: 0,
            unified: CursorUnifiedBilling(creditBalance: nil, usageStatus: ["monthlyUsage": ["usedCents": 0]])
        )
        XCTAssertEqual(uncapped.lines.last, .values(label: "On-demand", values: [MetricValue(number: 0, kind: .dollars)]))
    }

    private func assertPercent(_ mapped: CursorMappedUsage, _ label: String, _ expected: Double,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case .progress(_, let used, let limit, let format, _, _, _) =
            mapped.lines.first(where: { $0.label == label }) else {
            return XCTFail("Missing \(label)", file: file, line: line)
        }
        XCTAssertEqual(used, expected, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(limit, 100, file: file, line: line)
        XCTAssertEqual(format, .percent, file: file, line: line)
    }
}
