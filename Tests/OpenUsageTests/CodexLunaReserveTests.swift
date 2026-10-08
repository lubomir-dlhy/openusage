import XCTest
@testable import OpenUsage

final class CodexLunaReserveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_466_000)

    private func map(_ json: String) throws -> CodexMappedUsage {
        try CodexUsageMapper.mapUsageResponse(HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)), now: now)
    }

    func testMapsTheLunaReserveWeeklyPool() throws {
        // Shape from a live Pro response.
        let mapped = try map("""
        { "plan_type": "pro",
          "rate_limit": { "primary_window": { "used_percent": 12, "limit_window_seconds": 604800,
                                              "reset_after_seconds": 489704, "reset_at": 1791955714 },
                          "secondary_window": null },
          "additional_rate_limits": [
            { "limit_name": "gpt-reserve", "metered_feature": "base_model_inference",
              "rate_limit": { "primary_window": { "used_percent": 7, "limit_window_seconds": 604800,
                                                  "reset_after_seconds": 604800, "reset_at": 1792070811 },
                              "secondary_window": null },
              "normal_model_slug": "gpt-5.6-luna" } ] }
        """)
        guard case let .progress(_, used, limit, _, resetsAt, _, _)? = mapped.lines.first(where: { $0.label == "Luna Reserve" })
        else { return XCTFail("missing Luna Reserve line: \(mapped.lines.map(\.label))") }
        XCTAssertEqual(used, 7)
        XCTAssertEqual(limit, 100)
        XCTAssertEqual(resetsAt, Date(timeIntervalSince1970: 1_792_070_811))
        XCTAssertFalse(mapped.lines.contains { $0.label == "Spark" || $0.label == "Spark Weekly" })
    }

    func testPlansWithoutTheReserveEmitNoLine() throws {
        let mapped = try map("""
        { "plan_type": "prolite",
          "rate_limit": { "primary_window": { "used_percent": 31, "limit_window_seconds": 604800, "reset_at": 1791955714 } },
          "additional_rate_limits": [] }
        """)
        XCTAssertFalse(mapped.lines.contains { $0.label == "Luna Reserve" })
    }
}
