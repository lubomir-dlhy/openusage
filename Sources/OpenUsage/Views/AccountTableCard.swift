import SwiftUI

/// One account row's resolved content, built by `WidgetGroupedListView`.
struct AccountTableRow: Identifiable {
    let group: ProviderGroup
    let name: String
    /// Full name for the hover tooltip; the row name truncates in its fixed column.
    let fullName: String
    let plan: String?
    var renewal: SubscriptionRenewal?
    let entries: [AccountTable.Entry]
    let notice: String?
    let staleness: StalenessHint?
    let refreshing: Bool
    let isExpanded: Bool
    var id: String { group.provider.id }
}

/// Compact-density card for a provider with several accounts: shared limit columns, one row per
/// account, the account's full card unfolding under its row on click.
struct AccountTableCard<Detail: View, Menu: View, RowGesture: Gesture>: View {
    let familyName: String
    let icon: IconSource
    let rows: [AccountTableRow]
    let reorderSpaceName: String
    let activeRowID: String?
    let onToggle: (String) -> Void
    let onToggleAll: () -> Void
    @ViewBuilder let detail: (AccountTableRow, Set<String>) -> Detail
    @ViewBuilder let menu: (ProviderGroup) -> Menu
    let rowGesture: (ProviderGroup) -> RowGesture

    private static var nameWidth: CGFloat { 156 }
    /// Balance columns (credits) matter less than the limits, so they take a narrow fixed column and
    /// the limit bars share the rest.
    private static var balanceWidth: CGFloat { 84 }

    var body: some View {
        let columns = AccountTable.columns(rows.map(\.entries))
        let limitColumns = Set(rows.flatMap(\.entries).filter(\.data.isBounded).map(\.data.title))
        let anyExpanded = rows.contains(where: \.isExpanded)
        VStack(alignment: .leading, spacing: 6) {
            header(expanded: anyExpanded)
            if !columns.isEmpty {
                columnHeader(columns, limitColumns: limitColumns)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().opacity(0.5) }
                accountRow(row, columns: columns, limitColumns: limitColumns)
                if row.isExpanded {
                    let shown = Set(columns.compactMap { AccountTable.cell(for: $0, in: row.entries)?.id })
                    detail(row, shown)
                        .padding(.horizontal, -4)
                        .padding(.top, 2)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
                        .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardSurface()
    }

    private func header(expanded: Bool) -> some View {
        Button(action: onToggleAll) {
            HStack(spacing: 6) {
                ProviderIcon(source: icon, inset: 0.04)
                    .frame(width: 14, height: 14)
                Text(familyName)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(rows.count) accounts")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if let total = AccountTable.totalLast30Spend(rows.map(\.entries)) {
                    Text("·").foregroundStyle(.tertiary)
                    Text("30d " + MetricFormatter.number(total, kind: .dollars, style: .tray))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .hoverTooltip(spendTooltip(total: total))
                }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse all \(familyName) accounts" : "Expand all \(familyName) accounts")
    }

    private func spendTooltip(total: Double) -> String {
        let accounts = rows.compactMap { row in
            AccountTable.last30Spend(in: row.entries).map {
                "\(row.name): " + MetricFormatter.number($0, kind: .dollars, style: .full)
            }
        }
        return (["Last 30 days, all accounts: " + MetricFormatter.number(total, kind: .dollars, style: .full)]
            + accounts + ["Estimated from local usage at API rates"]).joined(separator: "\n")
    }

    private func columnHeader(_ columns: [String], limitColumns: Set<String>) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: Self.nameWidth, height: 1)
            ForEach(columns, id: \.self) { title in
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: limitColumns.contains(title) ? nil : Self.balanceWidth, alignment: .leading)
                    .frame(maxWidth: limitColumns.contains(title) ? .infinity : nil, alignment: .leading)
                    .hoverTooltip(title)
            }
        }
    }

    private func accountRow(_ row: AccountTableRow, columns: [String], limitColumns: Set<String>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AccountTableNameColumn(row: row)
                .frame(width: Self.nameWidth, alignment: .leading)
            ForEach(columns, id: \.self) { title in
                AccountTableCell(entry: AccountTable.cell(for: title, in: row.entries), title: title)
                    .frame(width: limitColumns.contains(title) ? nil : Self.balanceWidth, alignment: .leading)
                    .frame(maxWidth: limitColumns.contains(title) ? .infinity : nil, alignment: .leading)
            }
            if columns.isEmpty { Spacer(minLength: 0) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle(row.id) }
        .opacity(activeRowID == row.id ? 0 : 1)
        .highPriorityGesture(rowGesture(row.group))
        .contextMenu { menu(row.group) }
        .reorderFrame(id: row.id, in: .named(reorderSpaceName))
    }
}

private struct AccountTableNameColumn: View {
    let row: AccountTableRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(row.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                    .hoverTooltip(row.fullName)
                if let notice = row.notice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .hoverTooltip(notice)
                } else if let staleness = row.staleness, !row.refreshing {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .hoverTooltip(staleness.tooltip)
                }
                if row.refreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            if let subline {
                Text(subline)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .hoverTooltip(sublineTooltip)
            }
            let resets = AccountTable.resets(in: row.entries)
            if row.renewal != nil || resets != nil {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 5) {
                        if let renewal = row.renewal {
                            AccountRenewalChip(renewal: renewal, now: context.date)
                        }
                        if let resets {
                            AccountResetsChip(resets: resets, now: context.date)
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
    }

    private var spend: Double? { AccountTable.last30Spend(in: row.entries) }

    private var subline: String? {
        let parts = [row.plan, spend.map { "30d " + MetricFormatter.number($0, kind: .dollars, style: .tray) }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var sublineTooltip: String? {
        let parts = [
            row.plan.map { "Plan: \($0)" },
            spend.map { "Last 30 days: " + MetricFormatter.number($0, kind: .dollars, style: .full) }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

/// A small capsule tag under an account's name; the details live in its tooltip.
private struct AccountChip: View {
    let icon: String
    let text: String
    var iconStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    let tooltip: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconStyle)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
        .hoverTooltip(tooltip)
    }
}

private func countdown(_ remaining: TimeInterval) -> String {
    Formatters.expiryCountdown(remaining) ?? Formatters.imminent
}

/// "💳 25 Oct": when the subscription renews.
private struct AccountRenewalChip: View {
    let renewal: SubscriptionRenewal
    let now: Date

    var body: some View {
        AccountChip(icon: "creditcard", text: renewal.date.formatted(.dateTime.month(.abbreviated).day()), tooltip: tooltip)
    }

    private var tooltip: String {
        var lines = [
            "Subscription renews " + renewal.date.formatted(date: .long, time: .omitted),
            "In " + countdown(renewal.date.timeIntervalSince(now))
        ]
        if renewal.estimated { lines.append("Estimated from the last billing date on record") }
        return lines.joined(separator: "\n")
    }
}

/// "↻ 2 · 29 Oct": how many limit resets and when the first expires; the icon takes the soonest's
/// severity color. The tooltip lists every reset.
private struct AccountResetsChip: View {
    let resets: AccountTable.Resets
    let now: Date

    var body: some View {
        let soonest = resets.soonest
        let text = soonest.map { "\(resets.count) · " + $0.formatted(.dateTime.month(.abbreviated).day()) }
            ?? "\(resets.count)"
        AccountChip(
            icon: "arrow.counterclockwise",
            text: text,
            iconStyle: soonest.map { Theme.meterFill(WidgetData.expirySeverity(secondsRemaining: $0.timeIntervalSince(now))) }
                ?? AnyShapeStyle(.secondary),
            tooltip: tooltip
        )
    }

    private var tooltip: String {
        let heading = resets.count == 1 ? "1 limit reset available" : "\(resets.count) limit resets available"
        let dates = resets.expiries.enumerated().map { index, date in
            "\(index + 1). Expires \(date.formatted(date: .abbreviated, time: .shortened)) (in \(countdown(date.timeIntervalSince(now))))"
        }
        return ([heading] + dates).joined(separator: "\n")
    }
}

private struct AccountTableCell: View {
    let entry: AccountTable.Entry?
    let title: String

    var body: some View {
        if let data = entry?.data {
            if data.isBounded {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    meter(data, now: context.date)
                }
            } else {
                values(data)
            }
        } else {
            Text("–")
                .font(.system(size: 13.5))
                .foregroundStyle(.tertiary)
                .hoverTooltip("No \(title) limit for this account")
        }
    }

    private func meter(_ data: WidgetData, now: Date) -> some View {
        let state = data.meterState(now: now)
        let reset = data.compactTrailingText(now: now)
        // Narrow columns drop the reset's minutes ("1d 23h" → "1d"), then the reset; never an ellipsis.
        let shortReset = reset?.split(separator: " ").first.map(String.init).flatMap { $0.first?.isNumber == true ? $0 : nil }
        let resets = [reset, shortReset].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(Set(resets)).sorted { $0.count > $1.count }, id: \.self) { text in
                    meterLine(data, state: state, reset: text)
                }
                meterLine(data, state: state, reset: nil)
            }
            AccountTableBar(fraction: data.fraction, severity: state.severity)
        }
        .hoverTooltip(meterTooltip(data, state: state, now: now))
    }

    private func meterLine(_ data: WidgetData, state: WidgetData.MeterState, reset: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if case .spent = state { flame(state) }
            if case .runningOut = state { flame(state) }
            Text(MetricFormatter.number(data.displayedValue, kind: data.kind, style: .row))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
            Spacer(minLength: 4)
            if let reset {
                Text(reset)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func flame(_ state: WidgetData.MeterState) -> some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 10))
            .foregroundStyle(state.severity.map(Theme.meterFill) ?? AnyShapeStyle(Color.secondary))
    }

    private func meterTooltip(_ data: WidgetData, state: WidgetData.MeterState, now: Date) -> String {
        [ "\(title): \(data.headline)", data.resetTooltip(now: now), state.tooltip ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// "used · off" → "off": the cell keeps one word; the tooltip carries the full reading.
    private func lastWord(_ label: String) -> String {
        label.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces) ?? label
    }

    private func values(_ data: WidgetData) -> some View {
        let style: MetricFormatter.Style = data.showsFullValues ? .full : .row
        let selected = data.selectedValues
        // A lone labelled value ("$0.00 used · off") splits so the amount keeps the first line.
        let parts = selected.count == 1 && selected[0].label != nil
            ? [MetricFormatter.number(selected[0].number, kind: selected[0].kind, style: style), lastWord(selected[0].label ?? "")]
            : selected.map { MetricFormatter.string(for: $0, style: style) }
        return VStack(alignment: .leading, spacing: 1) {
            Text(parts.first ?? data.headline)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .hoverTooltip("\(title): " + data.selectedValues.map { MetricFormatter.string(for: $0, style: .full) }
            .joined(separator: " · "))
    }
}

private struct AccountTableBar: View {
    let fraction: Double
    let severity: WidgetData.MeterSeverity?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(severity.map(Theme.meterFill) ?? AnyShapeStyle(Color.secondary))
                    .frame(width: fraction > 0 ? max(4, proxy.size.width * min(fraction, 1)) : 0)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
