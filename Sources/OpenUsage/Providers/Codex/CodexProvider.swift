import Foundation

@MainActor
final class CodexProvider: ProviderRuntime {
    let account: ProviderAccount
    let provider: Provider

    let authStore: CodexAuthStore
    let usageClient: CodexUsageClient
    let logUsageScanner: CodexLogUsageScanner
    let now: @Sendable () -> Date
    let pricing: @Sendable () async -> ModelPricing

    init(
        account: ProviderAccount = .makeDefault(providerID: "codex"),
        authStore: CodexAuthStore? = nil,
        usageClient: CodexUsageClient = CodexUsageClient(),
        logUsageScanner: CodexLogUsageScanner = CodexLogUsageScanner(),
        now: @escaping @Sendable () -> Date = Date.init,
        pricing: @escaping @Sendable () async -> ModelPricing = { await ModelPricingStore.shared.current() }
    ) {
        self.account = account
        self.provider = Provider(
            id: account.id,
            displayName: account.displayName(providerDisplayName: "Codex"),
            icon: account.iconFileName.map(IconSource.customFile) ?? .providerMark("codex"),
            links: [
                .init(label: "Status", url: "https://status.openai.com/"),
                .init(label: "Dashboard", url: "https://chatgpt.com/codex/settings/usage")
            ]
        )
        self.authStore = authStore ?? CodexAuthStore(configDir: account.configDir)
        self.usageClient = usageClient
        self.logUsageScanner = logUsageScanner
        self.now = now
        self.pricing = pricing
    }

    // Descriptor ids scoped by account id (`provider.id`); default account id == "codex" keeps "codex.*".
    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "\(provider.id).session", provider: provider, title: "Session"),
            .percent(id: "\(provider.id).weekly", provider: provider, title: "Weekly"),
            // Model-specific Spark limits (GPT-5.3-Codex-Spark), parsed from `additional_rate_limits`.
            // Declared right after Weekly so they group with the core rate-limit meters; seeded as
            // secondary (below the caret) and unpinned in `DefaultLayout`.
            .percent(id: "\(provider.id).spark", provider: provider, title: "Spark"),
            .percent(id: "\(provider.id).sparkWeekly", provider: provider, title: "Spark Weekly"),
            .combined(id: "\(provider.id).credits", provider: provider, title: "Extra Usage", metricLabel: "Credits"),
            .values(id: "\(provider.id).rateLimitResets", provider: provider, title: "Rate Limit Resets", metricLabel: "Rate Limit Resets", traySuffix: "resets", showsResetExpiries: true),
            .usageTrend(provider: provider)
        ] + WidgetDescriptor.spendTiles(provider: provider)
    }

    func hasLocalCredentials() async -> Bool {
        // Same sources as `refresh()`: auth.json candidates first, keychain as the fallback. Only a
        // usable access token counts (see `hasUsableAccessToken`) — an API-key-only auth.json can't
        // serve the usage API, so seeding it on would just show an error row.
        let fileCandidates = authStore.loadAuthCandidates()
        if fileCandidates.contains(where: \.hasUsableAccessToken) {
            return true
        }
        let keychain = await loadOffMainActor { [authStore] in authStore.loadKeychainAuth() }
        return keychain?.hasUsableAccessToken == true
    }

    func refresh() async -> ProviderSnapshot {
        let fileCandidates = authStore.loadAuthCandidates()
        var lastFallbackError: Error?

        for candidate in fileCandidates {
            do {
                return try await probe(authState: candidate)
            } catch let error as CodexAuthError where error.allowsAuthFallback {
                lastFallbackError = error
                continue
            } catch {
                return ProviderSnapshot.error(provider: provider, error: error)
            }
        }

        // The shared "Codex Auth" keychain holds a SINGLE login, so a non-default account that pins its own
        // CODEX_HOME must never fall back to it (it would silently show the default account's usage). Only
        // the default account (no explicit config dir) uses the keychain fallback.
        if !authStore.hasExplicitConfigDir,
           let keychainCandidate = await loadOffMainActor({ [authStore] in authStore.loadKeychainAuth() }) {
            do {
                return try await probe(authState: keychainCandidate)
            } catch {
                return ProviderSnapshot.error(provider: provider, error: error)
            }
        }

        if let lastFallbackError {
            return ProviderSnapshot.error(provider: provider, error: lastFallbackError)
        }
        return ProviderSnapshot.error(provider: provider, error: CodexAuthError.notLoggedIn)
    }

    private func probe(authState initialState: CodexAuthState) async throws -> ProviderSnapshot {
        var authState = initialState
        guard var accessToken = authState.auth.tokens?.accessToken, !accessToken.isEmpty else {
            if authState.auth.apiKey?.isEmpty == false {
                throw CodexAuthError.usageAPIKey
            }
            throw CodexAuthError.notLoggedIn
        }

        if authStore.needsRefresh(authState.auth) {
            // The `codex` CLI may have rotated the token on disk since we loaded it. Re-read the live
            // credential first and adopt its (newer) access token — refreshing our stale copy would send
            // an already-rotated refresh_token and trip `refresh_token_reused` (issue #516).
            if let live = reloadLiveAuth(source: authState.source),
               let liveToken = live.auth.tokens?.accessToken, !liveToken.isEmpty {
                authState = live
                accessToken = liveToken
            }
        }

        if authStore.needsRefresh(authState.auth),
           let refreshToken = authState.auth.tokens?.refreshToken,
           !refreshToken.isEmpty {
            let refreshed = try await refreshAccessToken(authState: &authState, refreshToken: refreshToken)
            accessToken = refreshed
        }

        let response = try await fetchUsageWithRetry(accessToken: accessToken, authState: &authState)
        // The access token may have rotated during the usage fetch's refresh-and-retry; read the live one.
        let currentToken = authState.auth.tokens?.accessToken ?? accessToken
        let resetCredits = await fetchResetCreditsBestEffort(
            accessToken: currentToken,
            accountID: authState.auth.tokens?.accountID
        )
        var mapped = try CodexUsageMapper.mapUsageResponse(response, resetCredits: resetCredits, now: now())

        // Local spend tiles, scanned natively from the Codex CLI's session rollouts and priced
        // through the shared pricing store. `scan` runs on the scanner actor, off the main actor.
        if let scan = await logUsageScanner.scan(now: now(), pricing: pricing()) {
            SpendTileMapper.appendTokenUsage(
                scan.series, to: &mapped.lines, now: now(),
                unknownModelsByDay: scan.unknownModelsByDay,
                modelUsage: scan.modelUsage,
                modelSourceNote: "From your Codex logs (estimated)"
            )
            // Merge ChatGPT's cloud analytics into the trend: tokens for the surfaces local logs
            // can't see (desktop, web, cloud exec), imputed by calibrating credits-per-token against
            // the local logs. Empty when the fetch fails or calibration is impossible, leaving the
            // trend exactly as before.
            let cloudExtra = await fetchCloudTrendExtraBestEffort(
                accessToken: currentToken,
                accountID: authState.auth.tokens?.accountID,
                series: scan.series
            )
            SpendTileMapper.appendUsageTrend(
                scan.series, cloudExtraTokensByDay: cloudExtra, to: &mapped.lines, now: now(),
                note: cloudExtra.isEmpty
                    ? "From your Codex logs (estimated)"
                    : "From your Codex logs + ChatGPT cloud analytics (estimated)"
            )
        }

        MetricLine.appendNoDataIfNeeded(&mapped.lines)
        return ProviderSnapshot.make(provider: provider, plan: mapped.plan, lines: mapped.lines, refreshedAt: now())
    }

    /// Fetches the cloud analytics and imputes per-day tokens for the non-CLI surfaces (see
    /// `CodexCloudUsage`). Best-effort like the reset-credit fetch: any failure — network, non-2xx,
    /// unparseable body — logs a warning and returns empty, so the trend stays local-only rather than
    /// failing the whole refresh.
    private func fetchCloudTrendExtraBestEffort(
        accessToken: String,
        accountID: String?,
        series: DailyUsageSeries
    ) async -> [String: Double] {
        let calendar = Calendar.current
        let end = now()
        guard let start = calendar.date(byAdding: .day, value: -30, to: end) else { return [:] }
        do {
            let response = try await usageClient.fetchDailyUsageBreakdown(
                accessToken: accessToken,
                accountID: accountID,
                startDate: DailyUsageAccumulator.dayKey(from: start),
                endDate: DailyUsageAccumulator.dayKey(from: end)
            )
            guard (200..<300).contains(response.statusCode), let body = ProviderParse.jsonObject(response.body) else {
                AppLog.warn(LogTag.plugin("codex"), "cloud analytics fetch returned \(response.statusCode); trend stays local-only")
                return [:]
            }
            var localTokensByDay: [String: Int] = [:]
            for day in series.daily {
                localTokensByDay[day.date, default: 0] += day.totalTokens
            }
            return CodexCloudUsage.estimatedCloudTokensByDay(
                cloudDays: CodexCloudUsage.parseDays(body),
                localTokensByDay: localTokensByDay
            )
        } catch {
            AppLog.warn(LogTag.plugin("codex"), "cloud analytics fetch failed; trend stays local-only: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Fetches the on-demand reset-credit balance (and per-credit expiry) without ever failing the
    /// refresh: this is supplementary to the usage metrics, so a network error, timeout, or non-2xx just
    /// yields `nil` and the mapper falls back to the count embedded in the usage body. Logged, not thrown —
    /// the user still gets Session/Weekly/Credits even if this endpoint is down.
    private func fetchResetCreditsBestEffort(accessToken: String, accountID: String?) async -> HTTPResponse? {
        do {
            return try await usageClient.fetchResetCredits(accessToken: accessToken, accountID: accountID)
        } catch {
            AppLog.warn(LogTag.plugin("codex"), "reset-credit fetch failed; using usage-body count: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchUsageWithRetry(accessToken: String, authState: inout CodexAuthState) async throws -> HTTPResponse {
        var working = authState
        defer { authState = working }
        return try await ProviderAuthRetry.fetch(
            token: accessToken,
            attempt: { try await self.usageClient.fetchUsage(accessToken: $0, accountID: working.auth.tokens?.accountID) },
            refreshAccessToken: {
                guard let refreshToken = working.auth.tokens?.refreshToken, !refreshToken.isEmpty else {
                    throw CodexAuthError.tokenExpired
                }
                do {
                    return try await self.refreshAccessToken(authState: &working, refreshToken: refreshToken)
                } catch let error as CodexAuthError {
                    throw error
                } catch {
                    throw CodexUsageError.connectionFailed
                }
            },
            connectionFailed: CodexUsageError.connectionFailed,
            authExpired: CodexAuthError.tokenExpired
        )
    }

    /// Re-reads the credential from its original source (the same on-disk file or keychain entry) so a
    /// token the `codex` CLI rotated out-of-band is picked up before we attempt our own refresh. Reads
    /// only that one source — matching how `codex` reads the single `auth.json` from `CODEX_HOME` —
    /// rather than re-scanning every candidate path.
    private func reloadLiveAuth(source: CodexAuthState.Source) -> CodexAuthState? {
        switch source {
        case .file(let path):
            return authStore.loadAuth(at: path)
        case .keychain:
            return authStore.loadKeychainAuth()
        }
    }

    private func refreshAccessToken(authState: inout CodexAuthState, refreshToken: String) async throws -> String {
        let response = try await usageClient.refreshToken(refreshToken)
        authState.auth.tokens?.accessToken = response.accessToken
        if let refreshToken = response.refreshToken {
            authState.auth.tokens?.refreshToken = refreshToken
        }
        if let idToken = response.idToken {
            authState.auth.tokens?.idToken = idToken
        }
        authState.auth.lastRefresh = OpenUsageISO8601.string(from: now())
        // Fail loudly: a swallowed save strands the rotated token on disk (next launch re-refreshes /
        // can surface a false "token expired"). The refreshed token works for this session, so log and
        // continue. This is also the only call site of authStore.save, so a genuinely undecodable
        // payload (CodexAuthError.invalidAuthPayload) now surfaces in the log instead of vanishing.
        do {
            try authStore.save(authState)
        } catch {
            AppLog.error(LogTag.auth("codex"), "failed to persist rotated credentials; using the refreshed token for this session only: \(error.localizedDescription)")
        }
        return response.accessToken
    }
}
