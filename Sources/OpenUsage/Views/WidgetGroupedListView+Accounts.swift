import SwiftUI

/// Compact density folds every provider with several accounts into one `AccountTableCard`, placed
/// where the first of those accounts sits in the provider order.
extension WidgetGroupedListView {
    enum DashboardSection: Identifiable {
        case provider(ProviderGroup)
        case accounts(family: String, groups: [ProviderGroup])

        var id: String {
            switch self {
            case .provider(let group): group.provider.id
            case .accounts(let family, _): "accounts:\(family)"
            }
        }
    }

    var dashboardSections: [DashboardSection] {
        let groups = layout.displayGroups
        guard density == .compact else { return groups.map(DashboardSection.provider) }
        let byFamily = Dictionary(grouping: groups) { AccountTable.family(of: $0.provider.id) }
        var placed = Set<String>()
        return groups.compactMap { group in
            let family = AccountTable.family(of: group.provider.id)
            guard let members = byFamily[family], members.count > 1 else { return .provider(group) }
            guard placed.insert(family).inserted else { return nil }
            return .accounts(family: family, groups: members)
        }
    }

    func accountsSection(family: String, groups: [ProviderGroup]) -> some View {
        let familyName = family.capitalized
        let rows = groups.map { accountRow($0, familyName: familyName) }
        return AccountTableCard(
            familyName: familyName,
            icon: groups[0].provider.icon,
            rows: rows,
            reorderSpaceName: reorderSpaceName,
            activeRowID: activeProviderID,
            onToggle: { id in
                withAnimation(Motion.spring) {
                    if expandedAccountRows.remove(id) == nil { expandedAccountRows.insert(id) }
                }
            },
            onToggleAll: {
                let ids = rows.map(\.id)
                withAnimation(Motion.spring) {
                    if rows.contains(where: \.isExpanded) {
                        expandedAccountRows.subtract(ids)
                    } else {
                        expandedAccountRows.formUnion(ids)
                    }
                }
            },
            detail: { row, shownIDs in accountDetail(row.group, excluding: shownIDs) },
            menu: { providerMenu($0) },
            rowGesture: { providerDragGesture(for: $0) }
        )
    }

    private func accountRow(_ group: ProviderGroup, familyName: String) -> AccountTableRow {
        let id = group.provider.id
        let record = container.accounts.records.first { $0.id == id }
        let displayName = container.displayName(for: group.provider)
        let entries = resolvedRows(group.alwaysShownWidgets, hideEmpty: false).map {
            AccountTable.Entry(id: $0.descriptor.id, data: $0.data, alwaysShown: true)
        } + resolvedRows(group.expandedWidgets, hideEmpty: false).map {
            AccountTable.Entry(id: $0.descriptor.id, data: $0.data, alwaysShown: false)
        }
        var fullName = [displayName]
        if let label = record?.label?.nilIfEmpty, label != displayName { fullName.append(label) }
        return AccountTableRow(
            group: group,
            name: AccountTable.rowName(
                displayName: displayName,
                recordLabel: record?.label,
                customLabel: record?.customLabel,
                familyName: familyName
            ),
            fullName: fullName.joined(separator: "\n"),
            plan: dataStore.plan(for: id),
            renewal: dataStore.renewal(for: id),
            entries: entries,
            notice: dataStore.headerNotice(for: id),
            staleness: dataStore.stalenessHint(for: id),
            refreshing: dataStore.refreshingProviderIDs.contains(id),
            isExpanded: expandedAccountRows.contains(id)
        )
    }

    /// The account's own rows minus what the table row already shows (limit columns, resets tag),
    /// then its links.
    private func accountDetail(_ group: ProviderGroup, excluding shownIDs: Set<String>) -> some View {
        let rows = resolvedRows(group.widgets, hideEmpty: true).filter {
            !shownIDs.contains($0.descriptor.id) && !$0.data.showsResetExpiries
        }
        return VStack(spacing: 0) {
            ForEach(rows) { entry in
                row(entry.descriptor, data: entry.data, in: group.provider.id, condensedTop: false)
            }
            if !group.provider.visibleLinks.isEmpty {
                ProviderLinksView(links: group.provider.visibleLinks)
            }
        }
        .padding(.bottom, 4)
    }
}
