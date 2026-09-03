import Foundation

/// The installed provider set and its canonical order. Both the menu-bar app and one-shot CLI build
/// their runtimes here so credentials, refresh behavior, pricing, and normalization can never drift.
@MainActor
enum ProviderCatalog {
    /// `claudeCards` carries the extra Claude account cards found by the launch account pass
    /// (`ProviderAccountAssembly`). Each becomes an ordinary runtime inserted right after the default
    /// Claude card, with credentials and usage logs pinned to exactly its own config dir. The empty
    /// default keeps the historical single-card set for focused tests and callers that intentionally
    /// skip the account pass.
    static func make(
        defaults: UserDefaults = .standard,
        claudeCards: [ClaudeAccountCard] = [],
        defaultClaudeExtraLogRoots: [URL] = [],
        defaultClaudeConfigDirs: [String] = [],
        claudeIdentityKeys: [String: String] = [:]
    ) -> [ProviderRuntime] {
        make(
            accounts: AccountsStore(defaults: defaults),
            defaults: defaults,
            claudeCards: claudeCards,
            defaultClaudeExtraLogRoots: defaultClaudeExtraLogRoots,
            defaultClaudeConfigDirs: defaultClaudeConfigDirs,
            claudeIdentityKeys: claudeIdentityKeys
        )
    }

    /// Default provider order (see AGENTS.md "## Providers"): the three established providers first,
    /// then every other provider alphabetically by display name. The fork's user-configured Claude and
    /// Codex accounts remain grouped after their default card; identity-discovered Claude cards follow
    /// the manually configured Claude cards.
    static func make(
        accounts: AccountsStore,
        defaults: UserDefaults = .standard,
        claudeCards: [ClaudeAccountCard] = [],
        defaultClaudeExtraLogRoots: [URL] = [],
        defaultClaudeConfigDirs: [String] = [],
        claudeIdentityKeys: [String: String] = [:]
    ) -> [ProviderRuntime] {
        // Default provider order (see AGENTS.md "## Providers"): the three established providers first,
        // then every other provider alphabetically by display name. Account cards slot in right after
        // their family's default card.
        //
        // Every baked `Provider.displayName` here is the DERIVED default — renames live only in the
        // account registry and are resolved at render time (`ProviderAccountRecord.resolvedDisplayName`),
        // so a baked name can never be a stale copy of one.
        let configuredClaude = accounts.accounts(for: "claude")
        let organizationCards = claudeCards.filter { $0.configDirPath == nil }
        let configDirectoryCards = claudeCards.filter { $0.configDirPath != nil }
        var automaticallyRepresentedConfigDirs = configDirectoryCards.compactMap(\.configDirPath)
        if !organizationCards.isEmpty {
            automaticallyRepresentedConfigDirs += defaultClaudeConfigDirs
        }
        let representedConfigDirs = Set(automaticallyRepresentedConfigDirs.map(canonicalConfigDir))
        let deduplicatedConfiguredClaude = configuredClaude.filter { account in
            guard !account.isDefault, let configDir = account.configDir else { return true }
            return !representedConfigDirs.contains(canonicalConfigDir(configDir))
        }
        var runtimes: [ProviderRuntime] = []
        if organizationCards.isEmpty {
            runtimes.append(ClaudeProvider(
                account: deduplicatedConfiguredClaude[0],
                authStore: ClaudeAuthStore(allowsDesktopFallback: configDirectoryCards.isEmpty),
                logUsageScanner: ClaudeLogUsageScanner(additionalRoots: defaultClaudeExtraLogRoots)
            ))
            runtimes += deduplicatedConfiguredClaude.dropFirst().map { ClaudeProvider(account: $0) }
        } else {
            runtimes += organizationCards.map {
                claudeAccountRuntime(card: $0, identityKey: claudeIdentityKeys[$0.id])
            }
            let representedIDs = Set(organizationCards.map(\.id))
            runtimes += deduplicatedConfiguredClaude.filter { !representedIDs.contains($0.id) }
                .map { ClaudeProvider(account: $0) }
        }
        runtimes += configDirectoryCards.map {
            claudeAccountRuntime(card: $0, identityKey: claudeIdentityKeys[$0.id])
        }
        runtimes += accounts.accounts(for: "codex").map { CodexProvider(account: $0) }
        runtimes += [
            CursorProvider(),
            AntigravityProvider(),
            CopilotProvider(defaults: defaults),
            DevinProvider(),
            GrokProvider(),
            OpenCodeProvider(),
            OpenRouterProvider(),
            ZAIProvider()
        ]
        return runtimes
    }

    private static func canonicalConfigDir(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    }

    /// An extra Claude account card: same provider machinery, credentials and logs pinned to one
    /// login. The scanner's parse cache is partitioned per card so distinct homes never share
    /// records.
    private static func claudeAccountRuntime(
        card: ClaudeAccountCard,
        identityKey: String?
    ) -> ClaudeProvider {
        if let configDirPath = card.configDirPath, let keychainLiteral = card.keychainLiteral {
            return ClaudeProvider(
                provider: ClaudeProvider.makeProvider(id: card.id, displayName: card.displayName),
                authStore: ClaudeAuthStore(
                    scope: .configDir(path: configDirPath, keychainLiteral: keychainLiteral),
                    expectedIdentityKey: identityKey ?? card.identityKey
                ),
                logUsageScanner: ClaudeLogUsageScanner(
                    cacheIdentityOverride: "claude-account:\(card.id)",
                    rootsOverride: [URL(fileURLWithPath: configDirPath)] + card.extraLogRoots
                ),
                allowsUnattributedPiUsage: card.allowsUnattributedPiUsage
            )
        }

        let identity = identityKey ?? card.identityKey
        let user = identity.split(separator: "|").first.map(String.init)
        return ClaudeProvider(
            provider: ClaudeProvider.makeProvider(id: card.id, displayName: card.displayName),
            authStore: ClaudeAuthStore(
                desktopOrganization: card.organizationID,
                expectedIdentityKey: identity,
                desktopOnly: card.usesDesktopCredentials,
                preferOrganizationScopedDesktop: !card.usesDesktopCredentials
            ),
            logUsageScanner: ClaudeLogUsageScanner(
                accountUUID: user,
                organizationUUID: card.organizationID,
                allowsUnattributedSessions: card.allowsUnattributedPiUsage
            ),
            allowsUnattributedPiUsage: card.allowsUnattributedPiUsage
        )
    }
}
