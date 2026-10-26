import SwiftUI

/// Billing sources for an account's payment tag in the account table: the opt-in Claude Desktop lookup
/// (Claude cards) and a manual day of the month, which wins over anything reported.
struct BillingDaySection: View {
    let providerID: String

    @Environment(AppContainer.self) private var container
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @AppStorage(ClaudeDesktopBillingSetting.key) private var readsClaudeDesktop = false

    private var isClaude: Bool { ProviderAccountID.family(of: providerID) == "claude" }

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            Text("Billing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 0) {
                if isClaude {
                    HStack(spacing: 10) {
                        Text("Read From Claude Desktop")
                        Spacer(minLength: 8)
                        Toggle("", isOn: $readsClaudeDesktop).settingsSwitchStyle()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, density.controlRowPadding)
                    Text("Uses Claude Desktop's signed-in claude.ai session to read billing dates for every Claude account it can see.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    Divider().padding(.horizontal, 12)
                }
                HStack(spacing: 10) {
                    Text("Billing Day")
                    Spacer(minLength: 8)
                    Picker("Billing Day", selection: billingDay) {
                        Text("Not Set").tag(Int?.none)
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(Int?.some(day))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, density.controlRowPadding)
                Text("Day of the month this subscription bills. Overrides the date the provider reports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            .cardSurface()
        }
    }

    private var billingDay: Binding<Int?> {
        Binding(
            get: { container.accounts.records.first { $0.id == providerID }?.billingDay },
            set: { container.accounts.setBillingDay(cardID: providerID, to: $0) }
        )
    }
}
