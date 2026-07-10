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
}
