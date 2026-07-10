import Foundation

/// One day of ChatGPT's Codex cloud analytics (`/backend-api/wham/usage/daily-token-usage-breakdown`):
/// per-surface credit consumption for the account, in the API's only unit — **percent of the plan's
/// credit allotment**. `cliCredits` is the `cli` surface (the usage the local log scanner also sees);
/// `totalCredits` sums every surface (CLI, desktop app, web, cloud `exec`, …).
struct CodexCloudUsageDay: Hashable, Sendable {
    var date: String            // "yyyy-MM-dd"
    var totalCredits: Double    // percent, all surfaces
    var cliCredits: Double      // percent, the `cli` surface only
}

/// Parses the cloud analytics response and estimates **tokens** for the account's non-CLI usage, so
/// the Usage Trend can show one merged series in one unit.
///
/// The endpoint refuses absolute units (always `"units": "percent"`), so tokens are imputed by
/// calibration: on days where the local logs saw usage, the `cli` surface's credits and the local
/// token count give a credits-per-token ratio; the other surfaces' credits divided by that ratio
/// estimate their tokens. The ratio drifts with model mix and input/output shape, so the result is an
/// estimate and is labeled as one. Calibration assumes the local logs are the account's CLI usage —
/// a second machine running the CLI inflates `cli` credits and deflates the cloud estimate.
enum CodexCloudUsage {
    /// Extracts the per-day credit totals from the analytics response body. Returns an empty list on
    /// any shape mismatch (the caller treats that like a failed fetch: trend stays local-only).
    static func parseDays(_ body: [String: Any]) -> [CodexCloudUsageDay] {
        guard let data = body["data"] as? [Any] else { return [] }
        return data.compactMap { raw in
            guard let entry = raw as? [String: Any],
                  let date = entry["date"] as? String,
                  let surfaces = entry["product_surface_usage_values"] as? [String: Any]
            else { return nil }
            var total = 0.0
            var cli = 0.0
            for (surface, value) in surfaces {
                guard let credits = ProviderParse.number(value), credits.isFinite, credits > 0 else { continue }
                total += credits
                if surface == "cli" { cli += credits }
            }
            return CodexCloudUsageDay(date: date, totalCredits: total, cliCredits: cli)
        }
    }

    /// Estimated tokens per day (`yyyy-MM-dd`) for the surfaces the local logs can't see.
    ///
    /// Returns an empty map when calibration is impossible — no overlap between local activity and the
    /// `cli` surface, or a degenerate ratio — so the trend quietly stays local-only rather than
    /// carrying numbers with nothing behind them.
    static func estimatedCloudTokensByDay(
        cloudDays: [CodexCloudUsageDay],
        localTokensByDay: [String: Int]
    ) -> [String: Double] {
        // Credits-per-token ratio from the overlap: days where both the local logs and the `cli`
        // surface saw usage. Summed across days (not averaged per day) so heavy days dominate and a
        // timezone-skewed light day can't swing the ratio.
        var overlapCredits = 0.0
        var overlapTokens = 0.0
        for day in cloudDays {
            guard day.cliCredits > 0, let tokens = localTokensByDay[day.date], tokens > 0 else { continue }
            overlapCredits += day.cliCredits
            overlapTokens += Double(tokens)
        }
        guard overlapTokens > 0, overlapCredits > 0 else { return [:] }
        let creditsPerToken = overlapCredits / overlapTokens

        var estimated: [String: Double] = [:]
        for day in cloudDays {
            let cloudOnlyCredits = day.totalCredits - day.cliCredits
            guard cloudOnlyCredits > 0 else { continue }
            let tokens = cloudOnlyCredits / creditsPerToken
            guard tokens.isFinite, tokens >= 1 else { continue }
            estimated[day.date] = tokens
        }
        return estimated
    }
}
