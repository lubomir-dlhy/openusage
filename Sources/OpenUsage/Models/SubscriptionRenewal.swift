import Foundation

/// What happens to a subscription at its next billing date.
struct SubscriptionRenewal: Hashable, Sendable, Codable {
    enum Status: String, Hashable, Sendable, Codable {
        /// Bills again on `date`.
        case renews
        /// Cancelled: access ends on `date`.
        case ends
        /// Switches to `newPlan` on `date`.
        case upgrades
        case downgrades
        /// Switches plans in a direction we can't rank (business or unfamiliar plans).
        case changes
        /// Projected from the billing day the user set; the provider reports nothing.
        case billingDay
    }

    var date: Date
    var status: Status
    var newPlan: String? = nil

    /// The next occurrence of a day-of-month billing day on or after today. Months without that day
    /// (the 31st in April) bill on their last day.
    static func next(billingDay: Int, after now: Date, calendar: Calendar = .current) -> Date? {
        guard (1...31).contains(billingDay) else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: today),
                  let days = calendar.range(of: .day, in: .month, for: month)
            else { return nil }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(billingDay, days.upperBound - 1)
            if let date = calendar.date(from: components), date >= today { return date }
        }
        return nil
    }
}
