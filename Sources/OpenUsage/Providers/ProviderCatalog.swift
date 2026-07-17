import Foundation

/// The installed provider set and its canonical order. Both the menu-bar app and one-shot CLI build
/// their runtimes here so credentials, refresh behavior, pricing, and normalization can never drift.
@MainActor
enum ProviderCatalog {
    static func make(defaults: UserDefaults = .standard) -> [ProviderRuntime] {
        make(accounts: AccountsStore(defaults: defaults), defaults: defaults)
    }

    /// Default provider order (see AGENTS.md "## Providers"): the three established providers first,
    /// then every other provider alphabetically by display name. Claude and Codex support multiple
    /// accounts — one runtime per configured account (the default account first, then user-added
    /// extras), grouped right after the provider's default slot. With no extra accounts configured
    /// this is identical to the single-instance-per-provider list.
    static func make(accounts: AccountsStore, defaults: UserDefaults = .standard) -> [ProviderRuntime] {
        var providers: [ProviderRuntime] = []
        providers += accounts.accounts(for: "claude").map { ClaudeProvider(account: $0) }
        providers += accounts.accounts(for: "codex").map { CodexProvider(account: $0) }
        providers.append(CursorProvider())
        providers.append(AntigravityProvider())
        providers.append(CopilotProvider(defaults: defaults))
        providers.append(DevinProvider())
        providers.append(GrokProvider())
        providers.append(OpenCodeProvider())
        providers.append(OpenRouterProvider())
        providers.append(ZAIProvider())
        return providers
    }
}
