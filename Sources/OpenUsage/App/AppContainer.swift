import Foundation
import KeyboardShortcuts
import Observation

/// Composition root: owns the (constant) registry and the (mutable) stores, injected
/// into the SwiftUI environment.
@MainActor
@Observable
final class AppContainer {
    let registry: WidgetRegistry
    let layout: LayoutStore
    let dataStore: WidgetDataStore
    /// Accounts configured per provider. A multi-account provider (Claude, Codex) gets one runtime per
    /// account; everything downstream keys by the runtime's id (the account id, which == providerID for
    /// the default account). The Accounts settings UI drives this.
    let configuredAccounts: AccountsStore
    /// Opt-in private iCloud document sync for additive machine-local daily history.
    let iCloudSync: ICloudUsageSyncStore
    /// Single source of truth for which providers the user has turned off. Both stores consult it (via
    /// injected closures) and the Customize provider list drives it.
    let enablement: ProviderEnablementStore
    /// Providers that need a user-supplied API key (currently OpenRouter and Z.ai), conforming to
    /// `APIKeyManaging`. Each matching Customize provider detail shows an API Key section and writes
    /// changes through the capability. Empty when no installed provider needs a user key.
    let apiKeyProviders: [any APIKeyManaging]
    /// Quota pace notification preferences (three independent triggers). Drives the Settings section
    /// and is read by `WidgetDataStore.evaluateNotifications`.
    let notificationSettings: NotificationSettingsStore
    /// Source of truth for the popover's transparency: the persisted Increase Transparency toggle, the
    /// ephemeral secret-code easter-egg state, and the system accessibility flags it yields to. Read by both
    /// the SwiftUI surface and the AppKit panel (`StatusItemController`).
    let transparency: PopoverTransparencyStore
    /// The menu bar's screen-share privacy mode: the persisted Hide From Screen Share toggle
    /// plus the live capture signal. Read by `StatusItemImageUpdater` to swap the strip for the
    /// wordmark while the screen is shared or recorded.
    let privacy: MenuBarPrivacyStore
    /// One-time onboarding state (the first-run Customize hint card). Only ever marked pending by
    /// `FirstRunSeeder` on a fresh install, so existing installs never see the card.
    let onboarding: OnboardingStore
    /// The account registry the launch pass reconciled. The UI observes it live: a rename
    /// (`customLabel`) re-titles the card everywhere without a relaunch.
    let accounts: ProviderAccountsStore
    /// Claims Codex reset credits and Claude reset grants from the resets popover (the app's only
    /// provider-API writes), keyed by provider id. Each service shares its card's credentials. The view
    /// tree reads the matching service for each card's resets popover. Rebuilt with the runtimes on an
    /// account change, so a claim always runs on the runtime that refreshes the card.
    private(set) var resetClaims: [String: any ResetClaimService]
    /// The provider runtimes, kept so on-demand credential detection (the welcome screen and the
    /// Customize "Reset All" reseed) can re-probe `hasLocalCredentials()` on every card.
    private(set) var providers: [ProviderRuntime]
    /// Read-only usage API on 127.0.0.1:6736 for other local apps (silently off when the port is taken).
    private let localAPI: LocalUsageServer
    /// `nil` until `startRefreshing()`, which the welcome screen delays until the user has picked providers.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Watches `AccountsStore` and rebuilds the per-account runtimes in place when the account
    /// configuration changes (add/remove an account, or edit an existing one's icon/label/config dir).
    @ObservationIgnored private var accountsObserver: Task<Void, Never>?
    /// The new-provider credential-detection pass (see `NewProviderSeeder`); `nil` unless this launch is
    /// the first with a provider the install has never seen.
    private let newProviderTask: Task<Void, Never>?
    /// Persists a fresh `ShellEnvironmentSnapshot` once the login-shell capture completes, so the next
    /// launch can read shell-exported facts (provider home overrides) even when its own capture is slow.
    private let shellEnvironmentSnapshotTask: Task<Void, Never>

    /// `isFreshInstall` must be captured by the caller BEFORE `SettingsMigrator.migrate()` runs (the
    /// migrator's schema stamp makes the defaults domain non-empty). See `AppDelegate`.
    init(isFreshInstall: Bool = false) async {
        // Capture the user's login-shell environment off-main so provider keys exported in a shell
        // profile (e.g. OPENROUTER_API_KEY) resolve in a Finder/Dock-launched build, not only when
        // run from a terminal. Warmed here so the first refresh finds the cache ready.
        LoginShellEnvironment.shared.prewarm()
        // Once the capture lands, persist its identity-relevant facts so the NEXT launch has them
        // even if that launch's own capture is slow (see `ShellEnvironmentSnapshot`).
        self.shellEnvironmentSnapshotTask = ShellEnvironmentSnapshotStore(defaults: .standard).startRefreshTask()
        // The launch account pass: which account is signed in at each family's default home, plus
        // the config-dir scan for extra Claude logins. Feeds the snapshot cache's account stamp,
        // reconciles the account registry, and hands the catalog its extra-card build plan.
        let accounts = ProviderAccountsStore()
        let accountAssembly = await ProviderAccountAssembly.make(accountsStore: accounts, waitsForLoginShell: true)
        self.accounts = accounts

        // Provider construction and order live in `ProviderCatalog` (shared with the one-shot CLI so
        // the runtimes can't drift). Preserve the fork's manually configured Claude/Codex accounts,
        // then add the account-first Claude cards discovered from local config dirs.
        let configuredAccounts = AccountsStore()
        let providers = ProviderCatalog.make(
            accounts: configuredAccounts,
            claudeCards: accountAssembly.claudeCards,
            defaultClaudeExtraLogRoots: accountAssembly.defaultClaudeExtraLogRoots,
            defaultClaudeConfigDirs: accountAssembly.defaultClaudeConfigDirs,
            codex: accountAssembly.codex,
            claudeIdentityKeys: accountAssembly.identityKeysByCard
        )
        let registry = WidgetRegistry.from(providers)
        let apiKeyProviders = providers.compactMap { $0 as? any APIKeyManaging }
        let enablement = ProviderEnablementStore()
        let notificationSettings = NotificationSettingsStore()
        let accountDefaults: ([String]) -> [String] = { metricIDs in
            DefaultLayout.expandingAccounts(metricIDs, providerIDs: registry.providers.map(\.id))
        }
        let layout = LayoutStore(
            registry: registry,
            defaultMetricIDs: accountDefaults(DefaultLayout.metricIDs),
            defaultPinnedMetricIDs: accountDefaults(DefaultLayout.pinnedMetricIDs),
            defaultExpandedMetricIDs: accountDefaults(DefaultLayout.expandedMetricIDs),
            isProviderEnabled: { [enablement] in enablement.isEnabled($0) }
        )
        let dataStore = WidgetDataStore(
            registry: registry,
            providers: providers,
            isProviderEnabled: { [enablement] in enablement.isEnabled($0) },
            orderedDescriptors: { [layout] in layout.visiblePlaced.compactMap { layout.descriptor(for: $0) } },
            notificationSettings: { notificationSettings },
            providerIdentityKeys: accountAssembly.identityKeysByCard,
            resolveDisplayName: { [accounts] in accounts.resolvedDisplayName(cardID: $0) }
        )
        let iCloudSync = ICloudUsageSyncStore(dataStore: dataStore)
        // Re-enabling a provider should fetch it promptly, so clear any leftover failure backoff before
        // the enablement wake refreshes. `weak` breaks the cycle (dataStore already captures enablement).
        enablement.onProviderEnabled = { [weak dataStore] id in dataStore?.clearFailureBackoff(for: id) }
        enablement.onChange = { [weak dataStore, weak iCloudSync] in
            dataStore?.providerEnablementDidChange()
            iCloudSync?.scheduleWrite()
        }
        // Fresh installs start with nothing on; the welcome screen turns on the user's picks. No-op on
        // every later launch.
        let onboarding = OnboardingStore()
        FirstRunSeeder.seedIfNeeded(
            isFreshInstall: isFreshInstall,
            providers: providers,
            enablement: enablement,
            onboarding: onboarding
        )
        // Providers added by an update get the same credential detection on their first launch — enabled
        // only when the user actually has the tool. Runs every launch; a no-op unless the registry has a
        // provider this install has never seen (fresh installs were just baselined by FirstRunSeeder).
        self.newProviderTask = NewProviderSeeder.reconcileIfNeeded(
            providers: providers,
            enablement: enablement
        )
        self.providers = providers
        self.onboarding = onboarding
        self.registry = registry
        self.enablement = enablement
        self.apiKeyProviders = apiKeyProviders
        self.notificationSettings = notificationSettings
        self.layout = layout
        self.dataStore = dataStore
        self.configuredAccounts = configuredAccounts
        self.iCloudSync = iCloudSync

        self.resetClaims = Self.makeResetClaims(providers: providers, dataStore: dataStore)

        self.transparency = PopoverTransparencyStore()
        self.privacy = MenuBarPrivacyStore()
        self.localAPI = LocalUsageServer(state: { [layout, enablement, dataStore, accounts] in
            LocalUsageAPI.State(
                enabledOrderedIDs: layout.orderedProviderIDs().filter { enablement.isEnabled($0) },
                knownIDs: Set(registry.providers.map(\.id)),
                snapshots: dataStore.snapshots,
                limitDescriptors: registry.limitDescriptorsByProvider,
                errors: dataStore.providerErrors
            )
            // API output is human-read too: resolve card titles at respond time so renames show,
            // exactly like every UI surface.
            .resolvingDisplayNames(accounts.resolvedDisplayNamesByCardID)
        })
        localAPI.start()

        // Apply account changes (add/remove, or edit icon/label/config dir) live: rebuild the per-account
        // runtimes and swap the registry into the stores in place, so the dashboard cards and the
        // menu-bar strip reflect the change without a relaunch.
        self.accountsObserver = Self.startAccountsObserver(
            accounts: configuredAccounts,
            claudeCards: accountAssembly.claudeCards,
            defaultClaudeExtraLogRoots: accountAssembly.defaultClaudeExtraLogRoots,
            defaultClaudeConfigDirs: accountAssembly.defaultClaudeConfigDirs,
            claudeIdentityKeys: accountAssembly.identityKeysByCard,
            layout: layout,
            dataStore: dataStore,
            onRebuild: { [weak self] providers in
                guard let self else { return }
                self.providers = providers
                self.resetClaims = Self.makeResetClaims(providers: providers, dataStore: self.dataStore)
            }
        )
        // Become the notification-center delegate so banners show while frontmost — a menu-bar accessory
        // effectively always is. Notification authorization is requested the first time a trigger is
        // turned on in Settings, not at launch — triggers default off. No-op under tests.
        AppNotifications.shared.registerAsDelegate()
    }

    deinit {
        refreshTask?.cancel()
        accountsObserver?.cancel()
        newProviderTask?.cancel()
        shellEnvironmentSnapshotTask.cancel()
    }

    /// The name a card renders under right now — the app-side face of the one resolver
    /// (`ProviderAccountRecord.resolvedDisplayName`). Live: a rename in the account registry
    /// re-titles the card everywhere without a relaunch. Non-account providers (no record) keep
    /// their static display name; `Provider.displayName` itself only ever carries the derived
    /// default, so the fallback can never be a stale rename.
    func displayName(for provider: Provider) -> String {
        accounts.resolvedDisplayName(cardID: provider.id) ?? provider.displayName
    }

    /// Whether the card has an account record a rename can attach to (accounts-model families only,
    /// and only once the account's identity has been observed at least once).
    func canRename(_ providerID: String) -> Bool {
        accounts.records.contains { $0.id == providerID }
    }

    /// Watch `AccountsStore` and, on each change, rebuild the runtimes + registry from the current
    /// accounts and apply them in place to the live stores (same instances, so the refresh loop / local
    /// API stays valid), then fetch. Captures the stores (not `self`), mirroring `refreshTask`.
    private static func startAccountsObserver(
        accounts: AccountsStore,
        claudeCards: [ClaudeAccountCard],
        defaultClaudeExtraLogRoots: [URL],
        defaultClaudeConfigDirs: [String],
        claudeIdentityKeys: [String: String],
        layout: LayoutStore,
        dataStore: WidgetDataStore,
        onRebuild: @escaping @MainActor ([ProviderRuntime]) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            for await _ in NotificationCenter.default.notifications(named: AccountsStore.didChangeNotification) {
                let providers = ProviderCatalog.make(
                    accounts: accounts,
                    claudeCards: claudeCards,
                    defaultClaudeExtraLogRoots: defaultClaudeExtraLogRoots,
                    defaultClaudeConfigDirs: defaultClaudeConfigDirs,
                    claudeIdentityKeys: claudeIdentityKeys
                )
                let registry = WidgetRegistry.from(providers)
                AppLog.info(.lifecycle, "accounts changed — rebuilding \(providers.count) runtimes live")
                layout.syncAccounts(registry)
                dataStore.updateProviders(registry: registry, providers: providers)
                onRebuild(providers)
                // A replaced icon keeps its file name (so the IconSource is unchanged) — drop the strip's
                // content-keyed cache so the new image is rendered.
                MenuBarStripRenderer.invalidateCache()
                await dataStore.refreshAll()
            }
        }
    }

    /// The resets popover's claim services, sharing each provider's credential loading and HTTP
    /// client so the claim's auth can't drift from the provider's. A claim forces a refresh so the
    /// meters and reset count reconcile before the popover shows its result.
    private static func makeResetClaims(
        providers: [ProviderRuntime],
        dataStore: WidgetDataStore
    ) -> [String: any ResetClaimService] {
        var resetClaims: [String: any ResetClaimService] = [:]
        for codex in providers.compactMap({ $0 as? CodexProvider }) {
            let id = codex.provider.id
            resetClaims[id] = CodexResetClaimService(
                authStore: codex.authStore,
                usageClient: codex.usageClient,
                refreshAfterClaim: { [weak dataStore] in
                    await ResetClaimRefresh.run(dataStore: dataStore, providerID: id, tag: "codex")
                }
            )
        }
        for claude in providers.compactMap({ $0 as? ClaudeProvider }) {
            let id = claude.provider.id
            resetClaims[id] = ClaudeResetClaimService(provider: claude, refreshAfterClaim: { [weak dataStore] in
                await ResetClaimRefresh.run(dataStore: dataStore, providerID: id, tag: "claude")
            })
        }
        return resetClaims
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Self.startPeriodicRefresh(dataStore: dataStore)
    }

    /// Re-runs first-launch credential detection on demand — the enablement half of the Customize
    /// "Reset All" action (`LayoutStore.resetToDefault` handles metrics, order, pins, and expansion).
    /// Delegates to `FirstRunSeeder.reseed`; returns its detection task so callers can await it.
    @discardableResult
    func reseedEnabledProviders() -> Task<Void, Never> {
        FirstRunSeeder.reseed(providers: providers, enablement: enablement)
    }

    /// Restores every user preference owned by the container while deliberately preserving provider
    /// credentials, the iCloud device identity, and cached usage snapshots.
    /// Launch at Login and Sparkle preferences are reset by `SettingsScreen` alongside this call.
    func resetAllSettings() {
        layout.resetToDefault()
        layout.menuBarStyle = .text
        reseedEnabledProviders()
        dataStore.resetDisplaySettings()
        notificationSettings.resetToDefaults()
        transparency.resetToDefaults()
        privacy.hideUsageWhileScreenSharing = false
        iCloudSync.enabled = false
        for key in [
            AppearanceSetting.key, TimeFormatSetting.key, DensitySetting.key,
            ReduceAnimationsSetting.key, LogLevelSetting.key, TotalSpendSetting.key,
            TotalSpendSetting.periodKey, TotalSpendSetting.metricKey,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        KeyboardShortcuts.reset(.togglePopover)
        AppearanceSetting.applyCurrent()
        AppLog.reloadLevel()
        AppLog.info(.config, "All settings reset to defaults")
    }

    /// Drives live updates: refresh on launch, then again every refresh interval. Each pass honors the
    /// cache, so it only hits the network once a snapshot has actually expired. `@Observable` propagates
    /// the resulting snapshot changes to the menu-bar label and any open widgets, so the UI refreshes on
    /// its own instead of only when the popover opens.
    ///
    /// Between passes the loop sleeps via `RefreshWakeSignal`, which wakes it early when the user
    /// enables/disables a provider so a newly-enabled provider is fetched promptly instead of waiting out
    /// the full interval. The signal subscribes BEFORE the first pass and buffers, so an enablement change
    /// landing while a pass is still running (`NewProviderSeeder`, the Customize "Reset All" reseed —
    /// both of which typically finish faster than the network fetches) is
    /// never lost. Each pass still honors the cache (and the per-provider failure backoff), so an early
    /// wake only hits the network for a provider whose snapshot has actually expired.
    ///
    /// The wake is deliberately scoped to `ProviderEnablementStore.didChangeNotification` — NOT the
    /// firehose `UserDefaults.didChangeNotification`, which fires for the app's own snapshot-cache writes,
    /// Sparkle's update bookkeeping, and unrelated global-domain changes from other processes. Waking on
    /// that, with no minimum interval before re-refreshing, collapsed the fixed 5-minute cadence into a
    /// refresh storm.
    private static func startPeriodicRefresh(dataStore: WidgetDataStore) -> Task<Void, Never> {
        Task {
            let wakeSignal = RefreshWakeSignal()
            while !Task.isCancelled {
                await dataStore.refreshAll()
                // Re-evaluate quota pace milestones every tick — after the refresh so it sees fresh data,
                // and on every loop (not just on a fetch) so pace worsening from elapsed time alone still
                // alerts even with the popover closed.
                await dataStore.evaluateNotifications()
                await wakeSignal.waitForWake(timeout: RefreshSetting.interval)
            }
        }
    }
}
