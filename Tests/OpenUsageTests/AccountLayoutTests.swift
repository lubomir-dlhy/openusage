import Foundation
import Testing
@testable import OpenUsage

/// Phase 3: per-account layout defaults + enablement. A newly-added account is seeded with its provider's
/// default metrics/pins (account-scoped), single-account installs are unchanged, and enable/disable +
/// ordering work per account id.
@MainActor
struct AccountLayoutTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AccountLayoutTests-\(UUID().uuidString)")!
    }

    private func workClaude() -> ClaudeProvider {
        ClaudeProvider(account: ProviderAccount(
            id: "claude#1", providerID: "claude", label: "Work", configDir: "/w", iconFileName: nil
        ))
    }

    // MARK: DefaultLayout.expanded

    @Test func expandsBaseIDsToExtraAccounts() {
        let ids = DefaultLayout.expanded(
            ["claude.session", "claude.weekly", "antigravity.geminiPro"],
            forAccountIDs: ["claude", "claude#1", "antigravity"]
        )
        #expect(ids.contains("claude.session"))
        #expect(ids.contains("claude#1.session"))
        #expect(ids.contains("claude#1.weekly"))
        // A provider with no extra account is unchanged and not duplicated.
        #expect(ids.filter { $0 == "antigravity.geminiPro" }.count == 1)
    }

    @Test func unchangedWithoutExtraAccounts() {
        let base = ["claude.session", "codex.weekly"]
        #expect(DefaultLayout.expanded(base, forAccountIDs: ["claude", "codex"]) == base)
    }

    // MARK: LayoutStore end-to-end

    @Test func layoutSeedsBothAccountsOnFreshInstall() {
        let registry = WidgetRegistry.from([ClaudeProvider(), workClaude()])
        let layout = LayoutStore(registry: registry, defaults: freshDefaults())
        let placed = Set(layout.placed.map(\.descriptorID))
        #expect(placed.contains("claude.session"))    // default account
        #expect(placed.contains("claude#1.session"))  // extra account
        #expect(layout.providerOrder.contains("claude"))
        #expect(layout.providerOrder.contains("claude#1"))
        // Each account is its own display group.
        let groupIDs = layout.displayGroups.map(\.provider.id)
        #expect(groupIDs.contains("claude"))
        #expect(groupIDs.contains("claude#1"))
    }

    @Test func singleAccountLayoutUnchanged() {
        let registry = WidgetRegistry.from([ClaudeProvider()])
        let layout = LayoutStore(registry: registry, defaults: freshDefaults())
        let placed = Set(layout.placed.map(\.descriptorID))
        #expect(placed.contains("claude.session"))
        #expect(!placed.contains(where: { $0.contains("#") }))  // no account-scoped ids leak in
    }

    // MARK: Live account changes (syncAccounts) — applied without relaunch

    @Test func syncAccountsSeedsAddedAccountLive() {
        let layout = LayoutStore(registry: WidgetRegistry.from([ClaudeProvider()]), defaults: freshDefaults())
        #expect(!layout.providerOrder.contains("claude#1"))

        layout.syncAccounts(WidgetRegistry.from([ClaudeProvider(), workClaude()]))

        let placed = Set(layout.placed.map(\.descriptorID))
        #expect(placed.contains("claude.session"))     // default account untouched
        #expect(placed.contains("claude#1.session"))   // added account seeded live
        #expect(layout.providerOrder.contains("claude#1"))
        #expect(layout.displayGroups.map(\.provider.id).contains("claude#1"))
    }

    @Test func syncAccountsDropsRemovedAccountLive() {
        let layout = LayoutStore(
            registry: WidgetRegistry.from([ClaudeProvider(), workClaude()]),
            defaults: freshDefaults()
        )
        #expect(layout.providerOrder.contains("claude#1"))

        layout.syncAccounts(WidgetRegistry.from([ClaudeProvider()]))

        let placed = Set(layout.placed.map(\.descriptorID))
        #expect(placed.contains("claude.session"))               // default kept
        #expect(!placed.contains(where: { $0.contains("#") }))   // removed account's metrics gone
        #expect(!layout.providerOrder.contains("claude#1"))
        #expect(!layout.displayGroups.map(\.provider.id).contains("claude#1"))
    }

    /// Editing an existing account's icon at runtime must reach the dashboard groups (and, via the same
    /// `provider.icon`, the menu-bar strip) — the bug where only the Settings row updated.
    @Test func syncAccountsPropagatesEditedIconToGroupsLive() {
        let layout = LayoutStore(registry: WidgetRegistry.from([ClaudeProvider()]), defaults: freshDefaults())
        let withIcon = ClaudeProvider(account: ProviderAccount(
            id: "claude", providerID: "claude", label: nil, configDir: nil, iconFileName: "claude.png"
        ))

        layout.syncAccounts(WidgetRegistry.from([withIcon]))

        let group = layout.displayGroups.first { $0.provider.id == "claude" }
        #expect(group?.provider.icon == .customFile("claude.png"))
    }

    // MARK: Per-account enablement

    @Test func enablementIsIndependentPerAccount() {
        let enablement = ProviderEnablementStore(defaults: freshDefaults())
        enablement.setEnabled(false, for: "claude#1")
        #expect(enablement.isEnabled("claude"))      // default account stays on
        #expect(!enablement.isEnabled("claude#1"))   // only the work account is off
    }
}
