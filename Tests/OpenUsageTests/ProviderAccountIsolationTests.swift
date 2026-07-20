import Foundation
import Testing
@testable import OpenUsage

/// Phase 1: each account reads its OWN credential source (config dir), and the Claude/Codex providers are
/// account-aware (id, display name, descriptor ids, and auth config dir all reflect the account).
@MainActor
struct ProviderAccountIsolationTests {
    // MARK: Claude auth store

    @Test func claudeConfigDirOverrideDrivesHomeAndDistinctKeychain() {
        let work = ClaudeAuthStore(environment: FakeEnvironment([:]), configDir: "/Users/x/CP/.claude")
        let personal = ClaudeAuthStore(environment: FakeEnvironment([:]), configDir: "/Users/x/.claude")
        #expect(work.claudeHomeOverride() == "/Users/x/CP/.claude")
        #expect(personal.claudeHomeOverride() == "/Users/x/.claude")
        // Distinct config dirs hash to distinct keychain services → two accounts never cross-talk.
        #expect(work.keychainServiceCandidates().first != personal.keychainServiceCandidates().first)
    }

    @Test func claudeConfigDirOverrideBeatsEnv() {
        let store = ClaudeAuthStore(
            environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/env/dir"]),
            configDir: "/account/dir"
        )
        #expect(store.claudeHomeOverride() == "/account/dir")
    }

    @Test func claudeNilConfigDirFallsBackToEnv() {
        let store = ClaudeAuthStore(environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/env/dir"]))
        #expect(store.claudeHomeOverride() == "/env/dir")
    }

    // MARK: Codex auth store

    @Test func codexConfigDirOverrideDrivesHomeAndPaths() {
        let store = CodexAuthStore(environment: FakeEnvironment([:]), configDir: "/Users/x/CP/.codex")
        #expect(store.codexHome() == "/Users/x/CP/.codex")
        #expect(store.authPaths() == ["/Users/x/CP/.codex/auth.json"])
        #expect(store.hasExplicitConfigDir)
    }

    @Test func codexDefaultHasNoExplicitConfigDir() {
        let store = CodexAuthStore(environment: FakeEnvironment([:]))
        #expect(!store.hasExplicitConfigDir)
        #expect(store.codexHome() == nil)
    }

    // MARK: Providers are account-aware

    @Test func claudeProviderReflectsAccount() {
        let work = ProviderAccount(id: "claude#1", providerID: "claude", label: "Work", configDir: "/w", iconFileName: nil)
        let provider = ClaudeProvider(account: work)
        #expect(provider.account.id == "claude#1")
        #expect(provider.provider.id == "claude#1")
        #expect(provider.provider.displayName == "Claude · Work")
        #expect(provider.authStore.configDirOverride == "/w")
        #expect(provider.widgetDescriptors.contains { $0.id == "claude#1.session" })
    }

    @Test func claudeDefaultProviderKeepsLegacyIDs() {
        let provider = ClaudeProvider()
        #expect(provider.provider.id == "claude")
        #expect(provider.provider.displayName == "Claude")
        #expect(provider.authStore.configDirOverride == nil)
        #expect(provider.widgetDescriptors.contains { $0.id == "claude.session" })
    }

    @Test func codexProviderReflectsAccount() {
        let work = ProviderAccount(id: "codex#1", providerID: "codex", label: "Work", configDir: "/w", iconFileName: nil)
        let provider = CodexProvider(account: work)
        #expect(provider.provider.id == "codex#1")
        #expect(provider.provider.displayName == "Codex · Work")
        #expect(provider.authStore.configDirOverride == "/w")
        #expect(provider.widgetDescriptors.contains { $0.id == "codex#1.session" })
    }

    @Test func providerWithoutMultiAccountSynthesizesDefaultAccount() {
        let provider = CursorProvider()
        #expect(provider.account.id == provider.provider.id)
        #expect(provider.account.isDefault)
    }

    // MARK: Phase 2 — registry keeps multiple accounts of one provider distinct

    @Test func registryKeepsAccountsDistinct() {
        let def = ClaudeProvider()
        let work = ClaudeProvider(
            account: ProviderAccount(id: "claude#1", providerID: "claude", label: "Work", configDir: "/w", iconFileName: nil)
        )
        let registry = WidgetRegistry.from([def, work])
        #expect(registry.providers.map(\.id).contains("claude"))
        #expect(registry.providers.map(\.id).contains("claude#1"))
        // Both accounts' descriptors coexist without colliding.
        #expect(registry.descriptor(id: "claude.session") != nil)
        #expect(registry.descriptor(id: "claude#1.session") != nil)
        #expect(registry.descriptors(for: "claude#1").allSatisfy { $0.providerID == "claude#1" })
        #expect(!registry.descriptors(for: "claude#1").isEmpty)
    }

    @Test func catalogKeepsConfiguredAndDiscoveredAccountsTogether() {
        let defaults = UserDefaults(suiteName: "ProviderCatalogAccountMerge-\(UUID().uuidString)")!
        let accounts = AccountsStore(defaults: defaults)
        accounts.addAccount(providerID: "claude", label: "Configured", configDir: "/configured")
        accounts.addAccount(providerID: "codex", label: "Work", configDir: "/codex-work")

        let runtimes = ProviderCatalog.make(
            accounts: accounts,
            defaults: defaults,
            claudeCards: [ClaudeAccountCard(
                id: "claude@abcd1234",
                displayName: "Claude abcd1234",
                configDirPath: "/discovered",
                keychainLiteral: "/discovered"
            )]
        )

        #expect(Array(runtimes.map(\.provider.id).prefix(6)) == [
            "claude", "claude#1", "claude@abcd1234", "codex", "codex#1", "cursor",
        ])
    }
}
