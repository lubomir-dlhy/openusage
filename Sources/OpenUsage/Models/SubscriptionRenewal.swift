import Foundation

/// When a subscription next bills. `estimated` is true when the date is projected from an older billing
/// anchor rather than reported for the current period.
struct SubscriptionRenewal: Hashable, Sendable, Codable {
    var date: Date
    var estimated: Bool

    /// The first billing date after `now`: `anchor` plus whole periods of `months`. Each step adds to the
    /// original anchor, so a Jan 31 anchor lands on Feb 28 and then Mar 31 rather than drifting.
    static func next(
        anchor: Date, months: Int = 1, after now: Date, calendar: Calendar = .current
    ) -> Date? {
        guard months > 0 else { return nil }
        var periods = 0
        while periods < 1200 {
            guard let date = calendar.date(byAdding: .month, value: periods * months, to: anchor) else { return nil }
            if date > now { return date }
            periods += 1
        }
        return nil
    }
}
