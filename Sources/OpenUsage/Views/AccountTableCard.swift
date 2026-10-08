import SwiftUI

/// One account row's resolved content, built by `WidgetGroupedListView`.
struct AccountTableRow: Identifiable {
    let group: ProviderGroup
    let name: String
    /// Full name for the hover tooltip; the row name truncates in its fixed column.
    let fullName: String
    let plan: String?
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

    private static var nameWidth: CGFloat { 138 }

    var body: some View {
        let columns = AccountTable.columns(rows.map(\.entries))
        let anyExpanded = rows.contains(where: \.isExpanded)
        VStack(alignment: .leading, spacing: 6) {
            header(expanded: anyExpanded)
            if !columns.isEmpty {
                columnHeader(columns)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().opacity(0.5) }
                accountRow(row, columns: columns)
                if row.isExpanded {
                    let shown = Set(columns.compactMap { AccountTable.cell(for: $0, in: row.entries)?.id })
                    detail(row, shown)
                        .padding(.horizontal, -10)
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
                    .font(.system(size: 13, weight: .semibold))
                Text("\(rows.count) accounts")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse all \(familyName) accounts" : "Expand all \(familyName) accounts")
    }

    private func columnHeader(_ columns: [String]) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: Self.nameWidth, height: 1)
            ForEach(columns, id: \.self) { title in
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hoverTooltip(title)
            }
        }
    }

    private func accountRow(_ row: AccountTableRow, columns: [String]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AccountTableNameColumn(row: row)
                .frame(width: Self.nameWidth, alignment: .leading)
            ForEach(columns, id: \.self) { title in
                AccountTableCell(entry: AccountTable.cell(for: title, in: row.entries), title: title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if columns.isEmpty { Spacer(minLength: 0) }
        }
        .padding(.vertical, 2)
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
        let resets = AccountTable.resets(in: row.entries)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(row.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .hoverTooltip(row.fullName)
                if let notice = row.notice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.orange)
                        .hoverTooltip(notice)
                } else if let staleness = row.staleness, !row.refreshing {
                    Image(systemName: "clock")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .hoverTooltip(staleness.tooltip)
                }
                if row.refreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            if let subline {
                Text(subline)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .hoverTooltip(sublineTooltip)
            }
            if let resets, let soonest = resets.soonest {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    resetsLine(resets, soonest: soonest, now: context.date)
                }
            } else if let resets {
                Text(resets.count == 1 ? "1 reset" : "\(resets.count) resets")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
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

    private func resetsLine(_ resets: AccountTable.Resets, soonest: Date, now: Date) -> some View {
        let remaining = soonest.timeIntervalSince(now)
        let countdown = Formatters.expiryCountdown(remaining) ?? Formatters.imminent
        let severity = WidgetData.expirySeverity(secondsRemaining: remaining)
        return HStack(spacing: 3) {
            Circle()
                .fill(Theme.meterFill(severity))
                .frame(width: 5, height: 5)
            Text(resets.count == 1 ? "1 reset · expires in \(countdown)" : "\(resets.count) resets · next in \(countdown)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.system(size: 9.5))
        .hoverTooltip(resetsTooltip(resets))
    }

    private func resetsTooltip(_ resets: AccountTable.Resets) -> String {
        let dates = resets.expiries.map { "Expires " + $0.formatted(date: .abbreviated, time: .shortened) }
        let heading = resets.count == 1 ? "1 limit reset available" : "\(resets.count) limit resets available"
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
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .hoverTooltip("No \(title) limit for this account")
        }
    }

    private func meter(_ data: WidgetData, now: Date) -> some View {
        let state = data.meterState(now: now)
        let reset = data.compactTrailingText(now: now)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if case .spent = state { flame(state) }
                if case .runningOut = state { flame(state) }
                Text(MetricFormatter.number(data.displayedValue, kind: data.kind, style: .row))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .layoutPriority(1)
                Spacer(minLength: 2)
                if let reset {
                    Text(reset)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            AccountTableBar(fraction: data.fraction, severity: state.severity)
        }
        .hoverTooltip(meterTooltip(data, state: state, now: now))
    }

    private func flame(_ state: WidgetData.MeterState) -> some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 8.5))
            .foregroundStyle(state.severity.map(Theme.meterFill) ?? AnyShapeStyle(Color.secondary))
    }

    private func meterTooltip(_ data: WidgetData, state: WidgetData.MeterState, now: Date) -> String {
        [ "\(title): \(data.headline)", data.resetTooltip(now: now), state.tooltip ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private func values(_ data: WidgetData) -> some View {
        let style: MetricFormatter.Style = data.showsFullValues ? .full : .row
        let parts = data.selectedValues.map { MetricFormatter.string(for: $0, style: style) }
        return VStack(alignment: .leading, spacing: 1) {
            Text(parts.first ?? data.headline)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: " · "))
                    .font(.system(size: 9))
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
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
