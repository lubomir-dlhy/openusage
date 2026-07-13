import XCTest
@testable import OpenUsage

/// Covers the cloud half of Codex's merged Usage Trend: parsing the ChatGPT analytics response and
/// imputing tokens for the non-CLI surfaces by calibrating credits-per-token against the local logs.
final class CodexCloudUsageTests: XCTestCase {
    func testParseDaysSumsSurfacesAndSeparatesCLI() throws {
        let body = try XCTUnwrap(ProviderParse.jsonObject(Data("""
        {
          "data": [
            {
              "date": "2026-06-11",
              "product_surface_usage_values": {
                "cli": 31.75, "desktop_app": 3.66, "web": 0.0, "exec": 0.0
              },
              "models": [{"model": "gpt-5.5", "speed": "standard", "credits": 35.41}]
            },
            {
              "date": "2026-06-12",
              "product_surface_usage_values": {
                "cli": 2.85, "exec": 2.08, "desktop_app": 0.66
              }
            }
          ],
          "units": "percent",
          "group_by": "day"
        }
        """.utf8)))

        let days = CodexCloudUsage.parseDays(body)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].date, "2026-06-11")
        XCTAssertEqual(days[0].totalCredits, 35.41, accuracy: 1e-9)
        XCTAssertEqual(days[0].cliCredits, 31.75, accuracy: 1e-9)
        XCTAssertEqual(days[1].totalCredits, 5.59, accuracy: 1e-9)
        XCTAssertEqual(days[1].cliCredits, 2.85, accuracy: 1e-9)
    }

    func testParseDaysToleratesMalformedEntries() throws {
        let body = try XCTUnwrap(ProviderParse.jsonObject(Data("""
        {"data": [
          "not a dict",
          {"date": "2026-06-13"},
          {"date": "2026-06-14", "product_surface_usage_values": {"cli": "junk", "web": 4.0}}
        ]}
        """.utf8)))

        let days = CodexCloudUsage.parseDays(body)
        XCTAssertEqual(days.count, 1, "entries without a surface map are dropped, junk values skipped")
        XCTAssertEqual(days[0].cliCredits, 0)
        XCTAssertEqual(days[0].totalCredits, 4.0)
        XCTAssertTrue(CodexCloudUsage.parseDays(["units": "percent"]).isEmpty, "missing data array → empty")
    }

    func testEstimateCalibratesAgainstLocalOverlapAndImputesCloudOnlyDays() {
        // Overlap: 40 credits of `cli` usage over days the local logs measured at 400M tokens
        // → 0.1 credits per 1M tokens. The desktop/exec credits then impute as tokens at that rate.
        let cloud = [
            CodexCloudUsageDay(date: "2026-06-20", totalCredits: 25, cliCredits: 25),
            CodexCloudUsageDay(date: "2026-06-21", totalCredits: 22, cliCredits: 15),
            CodexCloudUsageDay(date: "2026-06-22", totalCredits: 10, cliCredits: 0),
        ]
        let local = ["2026-06-20": 250_000_000, "2026-06-21": 150_000_000]

        let estimated = CodexCloudUsage.estimatedCloudTokensByDay(cloudDays: cloud, localTokensByDay: local)
        XCTAssertNil(estimated["2026-06-20"], "an all-CLI day has no cloud share to impute")
        XCTAssertEqual(try XCTUnwrap(estimated["2026-06-21"]), 70_000_000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(estimated["2026-06-22"]), 100_000_000, accuracy: 1,
                       "a locally-idle day imputes from its full cloud credits")
    }

    func testEstimateReturnsEmptyWithoutCalibrationOverlap() {
        // No day where both the local logs and the `cli` surface saw usage → no ratio → no estimates,
        // so the trend stays honestly local-only instead of carrying unfounded numbers.
        let cloudOnly = [CodexCloudUsageDay(date: "2026-06-21", totalCredits: 30, cliCredits: 0)]
        XCTAssertTrue(CodexCloudUsage.estimatedCloudTokensByDay(
            cloudDays: cloudOnly, localTokensByDay: ["2026-06-20": 1_000_000]
        ).isEmpty)
        XCTAssertTrue(CodexCloudUsage.estimatedCloudTokensByDay(
            cloudDays: [CodexCloudUsageDay(date: "2026-06-21", totalCredits: 30, cliCredits: 10)],
            localTokensByDay: [:]
        ).isEmpty, "no local data at all → nothing to calibrate against")
    }

    func testEstimatedCloudUsagePricesTokensAtBlendedLocalRate() throws {
        // Local window: 400M tokens costing $40 → $0.10 per 1M tokens. Calibration (as in the token
        // test): 40 cli credits over 400M tokens. The imputed cloud tokens then price at that rate.
        let cloud = [
            CodexCloudUsageDay(date: "2026-06-20", totalCredits: 25, cliCredits: 25),
            CodexCloudUsageDay(date: "2026-06-21", totalCredits: 22, cliCredits: 15),
            CodexCloudUsageDay(date: "2026-06-22", totalCredits: 10, cliCredits: 0),
        ]
        let series = DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-06-20", totalTokens: 250_000_000, costUSD: 25),
            DailyUsageEntry(date: "2026-06-21", totalTokens: 150_000_000, costUSD: 15),
        ])

        let estimated = CodexCloudUsage.estimatedCloudUsageByDay(cloudDays: cloud, localSeries: series)

        XCTAssertNil(estimated["2026-06-20"], "an all-CLI day has no cloud share to impute")
        XCTAssertEqual(try XCTUnwrap(estimated["2026-06-21"]).tokens, 70_000_000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(estimated["2026-06-21"]).costUSD), 7.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(estimated["2026-06-22"]).costUSD), 10.0, accuracy: 0.001)
    }

    func testEstimatedCloudUsageLeavesCostNilWithoutLocalCostData() throws {
        let cloud = [CodexCloudUsageDay(date: "2026-06-21", totalCredits: 22, cliCredits: 15)]
        let series = DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-06-21", totalTokens: 150_000_000, costUSD: nil)
        ])

        let estimated = CodexCloudUsage.estimatedCloudUsageByDay(cloudDays: cloud, localSeries: series)

        XCTAssertEqual(try XCTUnwrap(estimated["2026-06-21"]).tokens, 70_000_000, accuracy: 1)
        XCTAssertNil(try XCTUnwrap(estimated["2026-06-21"]).costUSD, "no priced local day → nothing to blend a rate from")
    }

    func testMergedTileSeriesAddsCloudToLocalDaysAndCreatesIdleDays() {
        let series = DailyUsageSeries(daily: [
            DailyUsageEntry(date: "2026-06-21", totalTokens: 150_000_000, costUSD: 15)
        ])
        let cloud = [
            "2026-06-21": CodexCloudEstimate(tokens: 70_000_000, costUSD: 7),
            "2026-06-22": CodexCloudEstimate(tokens: 100_000_000, costUSD: 10),
        ]

        let merged = CodexCloudUsage.mergedTileSeries(series, cloudByDay: cloud)

        XCTAssertEqual(merged.daily.count, 2)
        let overlap = merged.daily.first { $0.date == "2026-06-21" }
        XCTAssertEqual(overlap?.totalTokens, 220_000_000)
        XCTAssertEqual(overlap?.costUSD ?? 0, 22, accuracy: 0.001)
        let cloudOnly = merged.daily.first { $0.date == "2026-06-22" }
        XCTAssertEqual(cloudOnly?.totalTokens, 100_000_000)
        XCTAssertEqual(cloudOnly?.costUSD ?? 0, 10, accuracy: 0.001, "a locally-idle day still gets a tile-visible entry")
        XCTAssertEqual(CodexCloudUsage.mergedTileSeries(series, cloudByDay: [:]), series, "no estimates → series untouched")
    }

    func testMergedTileModelUsageAppendsCloudRow() throws {
        let usage = ModelUsageSeries(daily: [
            DailyModelUsageEntry(date: "2026-06-21", models: [
                ModelUsageEntry(model: "gpt-5.5", totalTokens: 150_000_000, costUSD: 15)
            ])
        ])
        let cloud = [
            "2026-06-21": CodexCloudEstimate(tokens: 70_000_000, costUSD: 7),
            "2026-06-22": CodexCloudEstimate(tokens: 100_000_000, costUSD: 10),
        ]

        let merged = try XCTUnwrap(CodexCloudUsage.mergedTileModelUsage(usage, cloudByDay: cloud))

        let overlap = try XCTUnwrap(merged.daily.first { $0.date == "2026-06-21" })
        XCTAssertEqual(overlap.models.map(\.model), ["gpt-5.5", CodexCloudUsage.cloudModelName])
        XCTAssertEqual(overlap.models.last?.totalTokens, 70_000_000)
        let cloudOnly = try XCTUnwrap(merged.daily.first { $0.date == "2026-06-22" })
        XCTAssertEqual(cloudOnly.models.map(\.model), [CodexCloudUsage.cloudModelName])
        XCTAssertNil(CodexCloudUsage.mergedTileModelUsage(nil, cloudByDay: [:]), "nothing to merge stays nil")
        XCTAssertEqual(
            CodexCloudUsage.mergedTileModelUsage(nil, cloudByDay: cloud)?.daily.count, 2,
            "cloud estimates alone still produce a breakdown series"
        )
    }
}
