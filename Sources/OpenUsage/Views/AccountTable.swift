import Foundation

/// Several accounts of one provider folded into one card: shared limit columns, one row per account.
/// Pure layout decisions live here so the view stays thin and the rules stay testable.
enum AccountTable {
    struct Entry {
        let id: String
        let data: WidgetData
        let alwaysShown: Bool
    }

    struct Resets: Equatable {
        let count: Int
        let expiries: [Date]
        var soonest: Date? { expiries.min() }
    }

    static let maxColumns = 4

    /// `claude@ab12cd34` and the fork's configured `claude#1` both belong to `claude`.
    static func family(of cardID: String) -> String {
        cardID.firstIndex(where: { $0 == "@" || $0 == "#" }).map { String(cardID[..<$0]) } ?? cardID
    }

    /// Titles of the Always Visible limits any account reports, in first-seen order, then balances
    /// (credits) even when they sit On Demand. Charts, spend tiles, and reset counts get their own
    /// treatment, so they never become columns.
    static func columns(_ accounts: [[Entry]]) -> [String] {
        var titles: [String] = []
        let entries = accounts.flatMap { $0 }
        let alwaysShown = entries.filter { $0.alwaysShown && isColumnCandidate($0.data) }
        let balances = entries.filter { !$0.alwaysShown && !$0.data.isBounded && isColumnCandidate($0.data) }
        for entry in alwaysShown + balances where !titles.contains(entry.data.title) {
            titles.append(entry.data.title)
        }
        return Array(titles.prefix(maxColumns))
    }

    static func isColumnCandidate(_ data: WidgetData) -> Bool {
        guard data.hasData, !data.isChart, !data.isUsagePeriod, !data.showsResetExpiries else { return false }
        return data.isBounded || !data.selectedValues.isEmpty
    }

    static func cell(for title: String, in entries: [Entry]) -> Entry? {
        entries.first { $0.data.title == title && isColumnCandidate($0.data) && ($0.alwaysShown || !$0.data.isBounded) }
    }

    static func resets(in entries: [Entry]) -> Resets? {
        guard let data = entries.first(where: { $0.data.showsResetExpiries && $0.data.hasData })?.data,
              let count = data.values.first.map({ Int($0.number) }), count > 0
        else { return nil }
        return Resets(count: count, expiries: data.expiriesAt.sorted())
    }

    /// The Last 30 Days spend in dollars, when the account has local spend history.
    static func last30Spend(in entries: [Entry]) -> Double? {
        guard let data = entries.first(where: { $0.id.hasSuffix(".last30") && $0.data.hasData })?.data else {
            return nil
        }
        return data.values.first { $0.kind == .dollars }?.number
    }

    /// Last 30 Days spend summed across accounts; `nil` when none has local spend history.
    static func totalLast30Spend(_ accounts: [[Entry]]) -> Double? {
        let amounts = accounts.compactMap(last30Spend(in:))
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    /// The short name an account goes by inside its provider's card: a rename wins, then the account's
    /// own label (organization, else email), then the card title without the provider prefix.
    static func rowName(displayName: String, recordLabel: String?, customLabel: String?, familyName: String) -> String {
        if let custom = customLabel?.nilIfEmpty {
            return stripFamily(custom, familyName: familyName)
        }
        if let label = recordLabel?.nilIfEmpty {
            return shortLabel(label)
        }
        let stripped = stripFamily(displayName, familyName: familyName)
        return stripped.isEmpty || stripped == familyName ? "Default" : stripped
    }

    /// Account labels read "email (Org Name)". Claude names personal orgs "<email>'s Organization",
    /// which only repeats the email, so those fall back to the email.
    static func shortLabel(_ label: String) -> String {
        guard label.hasSuffix(")"), let open = label.lastIndex(of: "(") else { return label }
        let email = label[..<open].trimmingCharacters(in: .whitespaces)
        let org = label[label.index(after: open)..<label.index(before: label.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        if org.isEmpty || org.hasSuffix("'s Organization") { return email.isEmpty ? label : email }
        return org
    }

    private static func stripFamily(_ name: String, familyName: String) -> String {
        for separator in [" — ", " · ", ": ", " - "] where name.hasPrefix(familyName + separator) {
            return String(name.dropFirst(familyName.count + separator.count))
        }
        return name
    }
}
