import Foundation

struct ClaudeAccountCard: Equatable, Sendable {
    let id: String
    let identityKey: String
    let organizationID: String?
    let displayName: String
    let usesDesktopCredentials: Bool
    let allowsUnattributedPiUsage: Bool
    let configDirPath: String?
    let keychainLiteral: String?
    let extraLogRoots: [URL]

    init(
        id: String,
        identityKey: String,
        organizationID: String,
        displayName: String,
        usesDesktopCredentials: Bool,
        allowsUnattributedPiUsage: Bool
    ) {
        self.id = id
        self.identityKey = identityKey
        self.organizationID = organizationID
        self.displayName = displayName
        self.usesDesktopCredentials = usesDesktopCredentials
        self.allowsUnattributedPiUsage = allowsUnattributedPiUsage
        self.configDirPath = nil
        self.keychainLiteral = nil
        self.extraLogRoots = []
    }

    init(
        id: String,
        displayName: String,
        configDirPath: String,
        keychainLiteral: String,
        extraLogRoots: [URL] = [],
        identityKey: String = "",
        allowsUnattributedPiUsage: Bool = false
    ) {
        self.id = id
        self.identityKey = identityKey
        self.organizationID = nil
        self.displayName = displayName
        self.usesDesktopCredentials = false
        self.allowsUnattributedPiUsage = allowsUnattributedPiUsage
        self.configDirPath = configDirPath
        self.keychainLiteral = keychainLiteral
        self.extraLogRoots = extraLogRoots
    }
}

/// The launch-time account pass: read which account is signed in at each family's default home,
/// reconcile the account registry, and expose the per-card identity map that the snapshot cache's
/// account stamp consumes. Runs once per launch (app) or per invocation (one-shot CLI); a mid-run
/// swap is caught on the next launch.
@MainActor
struct ProviderAccountAssembly {
    /// Card id → the account identity signed in there this launch. Phase 1 observes only default
    /// homes, so the keys are the bare family ids; a family whose identity didn't resolve is absent.
    let identityKeysByCard: [String: String]
    var claudeCards: [ClaudeAccountCard] = []
    var defaultClaudeExtraLogRoots: [URL] = []

    /// `waitsForLoginShell`: true for the menu-bar app (a Finder/Dock launch inherits no shell
    /// exports, so the pass leans on the login-shell layers), false for the one-shot CLI (a terminal
    /// launch's process environment already carries the user's exports).
    static func make(
        defaults: UserDefaults = .standard,
        accountsStore: ProviderAccountsStore? = nil,
        waitsForLoginShell: Bool
    ) -> ProviderAccountAssembly {
        // The identity read needs the login shell's exports (CLAUDE_CONFIG_DIR/CODEX_HOME name the
        // default homes), and it reads them through the very same reader the provider auth stores
        // use — `ProcessEnvironmentReader`, which pins identity-relevant keys to the persisted
        // shell-environment snapshot for the whole session, so identity and usage resolve the same
        // homes no matter when the async capture lands. The one unreadable state is a genuinely
        // FIRST Finder/Dock launch: capture still cold and no snapshot persisted yet — a
        // shell-exported home override would be invisible, so that family's read must be skipped
        // rather than misread as "no override". The skip is per family: a family whose home override
        // is already visible in the process environment (a terminal launch, `launchctl setenv`)
        // doesn't need the shell layers at all and still resolves.
        let shellFactsReadable = !waitsForLoginShell
            || LoginShellEnvironment.shared.capturedSuccessfully
            || ShellEnvironmentSnapshotStore.launchSnapshot != nil
        let families = shellFactsReadable
            ? ProviderAccountID.families
            : ProviderAccountID.families.filter { family in
                guard let key = Self.homeOverrideKeys[family] else { return false }
                return ProcessInfo.processInfo.environment[key]?.nilIfEmpty != nil
            }
        if families.count < ProviderAccountID.families.count {
            AppLog.info(.config, "account identity read skipped for \(ProviderAccountID.families.subtracting(families).sorted().joined(separator: ", ")): login shell cold and no shell-environment snapshot exists yet")
        }
        return make(
            observer: DefaultAccountObserver(),
            accountsStore: accountsStore ?? ProviderAccountsStore(defaults: defaults),
            families: families,
            claudeDiscovery: ClaudeConfigDirDiscovery()
        )
    }

    /// The environment variable that relocates each family's default home — the fact whose
    /// invisibility (shell layers unreadable AND not in the process environment) makes that family's
    /// identity read unsafe on a first launch.
    private static let homeOverrideKeys: [String: String] = [
        "claude": "CLAUDE_CONFIG_DIR",
        "codex": "CODEX_HOME",
    ]

    /// The environment-independent core, separated so tests inject a fixed observer and scratch
    /// store. `families` limits the pass to the families whose home facts are readable this launch
    /// (see `make(defaults:waitsForLoginShell:)`); a family left out is simply not observed —
    /// no identity key, no reconciliation, exactly as if the pass never ran for it.
    static func make(
        observer: DefaultAccountObserver,
        accountsStore: ProviderAccountsStore,
        families: Set<String> = ProviderAccountID.families,
        claudeDiscovery: ClaudeConfigDirDiscovery? = nil,
        desktop: ClaudeDesktopAuthStore? = nil,
        listDesktopOrganizationDirectories: @escaping @Sendable (URL) -> [String] = { root in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return urls.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true
                else { return nil }
                return url.lastPathComponent
            }
        }
    ) -> ProviderAccountAssembly {
        var identityKeys: [String: String] = [:]
        var observations: [ProviderAccountsStore.AccountObservation] = []

        let outcomes: [(family: String, outcome: DefaultAccountObserver.Outcome)] = [
            ("claude", { observer.observeClaude() }),
            ("codex", { observer.observeCodex() }),
        ].compactMap { family, observe in
            families.contains(family) ? (family, observe()) : nil
        }
        for (family, outcome) in outcomes {
            switch outcome {
            case .resolved(let identityKey, let label, let anchor):
                identityKeys[family] = identityKey
                observations.append(ProviderAccountsStore.AccountObservation(
                    family: family,
                    identityKey: identityKey,
                    label: label,
                    sources: [ProviderAccountSource(kind: .defaultHome, anchor: anchor, holdsDefaultSource: true)]
                ))
                AppLog.info(.config, "accounts: \(family) default identity resolved (\(ProviderAccountID.make(family: family, identityKey: identityKey)))")
            case .unresolved(let reason):
                // The soak signal for later phases: how often a real login can't name its account.
                AppLog.info(.config, "accounts: \(family) default identity unresolved — \(reason)")
            case .absent:
                AppLog.debug(.config, "accounts: \(family) has no default login")
            }
        }

        // Keep the fork's custom-config-dir discovery alongside upstream's Claude Desktop
        // organization discovery. Config-directory credentials and logs stay pinned to their own
        // card; a second directory for the default identity is only an extra local log root.
        var foundConfigAccounts: [(
            identityKey: String,
            label: String?,
            dirs: [ClaudeConfigDirDiscovery.Finding]
        )] = []
        var defaultClaudeExtraLogRoots: [URL] = []
        let claudeOutcome = outcomes.first { $0.family == "claude" }?.outcome
        if let claudeDiscovery, let claudeOutcome, families.contains("claude") {
            if case .unresolved = claudeOutcome {
                AppLog.info(.config, "discovery: claude default login is unreadable; skipping config-dir candidates")
            } else {
                let defaultKey = identityKeys["claude"]
                let scan = claudeDiscovery.run()
                for note in scan.notes { AppLog.info(.config, "discovery: \(note)") }
                var order: [String] = []
                var grouped: [String: [ClaudeConfigDirDiscovery.Finding]] = [:]
                for finding in scan.findings {
                    if grouped[finding.identityKey] == nil { order.append(finding.identityKey) }
                    grouped[finding.identityKey, default: []].append(finding)
                }
                for identityKey in order {
                    let findings = grouped[identityKey] ?? []
                    let sources = findings.map {
                        ProviderAccountSource(
                            kind: .configDir,
                            anchor: $0.anchorPath,
                            holdsDefaultSource: false,
                            keychainLiteral: $0.keychainLiteral
                        )
                    }
                    if identityKey == defaultKey {
                        defaultClaudeExtraLogRoots += findings.map { URL(fileURLWithPath: $0.anchorPath) }
                        if let index = observations.firstIndex(where: {
                            $0.family == "claude" && $0.identityKey == identityKey
                        }) {
                            observations[index].sources += sources
                        }
                    } else {
                        observations.append(ProviderAccountsStore.AccountObservation(
                            family: "claude",
                            identityKey: identityKey,
                            label: findings.first?.label,
                            sources: sources
                        ))
                        foundConfigAccounts.append((identityKey, findings.first?.label, findings))
                    }
                }
            }
        }

        func configDirectoryCards(
            records: [ProviderAccountRecord],
            allowsUnattributedPiUsage: Bool
        ) -> [ClaudeAccountCard] {
            foundConfigAccounts.compactMap { account in
                guard let record = records.first(where: {
                    $0.family == "claude" && $0.identityKey == account.identityKey && !$0.removedTombstone
                }), record.id != "claude", let primary = account.dirs.first
                else { return nil }
                identityKeys[record.id] = account.identityKey
                return ClaudeAccountCard(
                    id: record.id,
                    displayName: record.derivedDisplayName,
                    configDirPath: primary.anchorPath,
                    keychainLiteral: primary.keychainLiteral,
                    extraLogRoots: account.dirs.dropFirst().map { URL(fileURLWithPath: $0.anchorPath) },
                    identityKey: account.identityKey,
                    allowsUnattributedPiUsage: allowsUnattributedPiUsage
                )
            }.sorted { $0.id < $1.id }
        }

        guard families.contains("claude") else {
            accountsStore.reconcile(with: observations)
            return ProviderAccountAssembly(identityKeysByCard: identityKeys)
        }

        if let claudeIdentity = identityKeys["claude"], !claudeIdentity.contains("|") {
            let records = accountsStore.reconcile(with: observations)
            let cards = configDirectoryCards(
                records: records,
                allowsUnattributedPiUsage: records.count { $0.family == "claude" } == 1
            )
            return ProviderAccountAssembly(
                identityKeysByCard: identityKeys,
                claudeCards: cards,
                defaultClaudeExtraLogRoots: defaultClaudeExtraLogRoots
            )
        }

        let desktop = desktop ?? ClaudeDesktopAuthStore(
            files: observer.files, homeDirectory: observer.homeDirectory
        )
        let desktopOrganizations = discoverDesktopOrganizations(
            desktop: desktop,
            cliIdentity: identityKeys["claude"],
            listDirectories: listDesktopOrganizationDirectories
        )
        let desktopAnchor = desktop.homeDirectory()
            .appendingPathComponent("Library/Application Support/Claude").path
        for organization in desktopOrganizations {
            let source = ProviderAccountSource(
                kind: .defaultHome, anchor: desktopAnchor, holdsDefaultSource: false
            )
            if let index = observations.firstIndex(where: {
                $0.family == "claude" && $0.identityKey == organization.identityKey
            }) {
                observations[index].sources.append(source)
            } else {
                observations.append(ProviderAccountsStore.AccountObservation(
                    family: "claude", identityKey: organization.identityKey,
                    label: organization.label, sources: [source]
                ))
            }
        }

        let defaultClaudeIdentity = identityKeys["claude"]
        let records = accountsStore.reconcile(with: observations)
        let allowsUnattributedPiUsage = records.count { $0.family == "claude" } == 1
        var cards = configDirectoryCards(
            records: records,
            allowsUnattributedPiUsage: allowsUnattributedPiUsage
        )
        if let defaultIdentity = defaultClaudeIdentity,
           let organization = defaultIdentity.split(separator: "|").last,
           defaultIdentity.contains("|"),
           let record = records.first(where: {
               $0.family == "claude" && $0.identityKey == defaultIdentity && !$0.removedTombstone
           })
        {
            let label = outcomes.first(where: { $0.family == "claude" }).flatMap { outcome -> String? in
                guard case .resolved(_, let value, _) = outcome.outcome else { return nil }
                return organizationLabel(value)
            } ?? "Organization"
            cards.append(ClaudeAccountCard(
                id: record.id, identityKey: defaultIdentity, organizationID: String(organization),
                displayName: "Claude — \(label)", usesDesktopCredentials: false,
                allowsUnattributedPiUsage: allowsUnattributedPiUsage
            ))
            identityKeys.removeValue(forKey: "claude")
            identityKeys[record.id] = defaultIdentity
        }
        for organization in desktopOrganizations where organization.identityKey != defaultClaudeIdentity {
            guard let record = records.first(where: {
                $0.family == "claude" && $0.identityKey == organization.identityKey && !$0.removedTombstone
            }) else { continue }
            let cardID = record.id
            guard !cards.contains(where: { $0.id == cardID }) else { continue }
            cards.append(ClaudeAccountCard(
                id: cardID, identityKey: organization.identityKey, organizationID: organization.id,
                displayName: "Claude — \(organizationLabel(record.label) ?? organization.label)",
                usesDesktopCredentials: true, allowsUnattributedPiUsage: allowsUnattributedPiUsage
            ))
            identityKeys[cardID] = organization.identityKey
        }

        return ProviderAccountAssembly(
            identityKeysByCard: identityKeys,
            claudeCards: cards,
            defaultClaudeExtraLogRoots: defaultClaudeExtraLogRoots
        )
    }

    private struct DesktopOrganization {
        var id: String
        var identityKey: String
        var label: String
    }

    private static func organizationLabel(_ value: String?) -> String? {
        guard let value, let opening = value.lastIndex(of: "("), value.last == ")" else { return value }
        return String(value[value.index(after: opening)..<value.index(before: value.endIndex)])
    }

    private static func discoverDesktopOrganizations(
        desktop: ClaudeDesktopAuthStore,
        cliIdentity: String?,
        listDirectories: @Sendable (URL) -> [String]
    ) -> [DesktopOrganization] {
        guard let user = desktop.lastKnownAccountUUID(), desktop.hasCredentialMaterial() else { return [] }
        let active = desktop.load(allowInteraction: false, expectedAccountUUID: user)
        let activeOrganization = active.organization

        let root = desktop.homeDirectory().appendingPathComponent("Library/Application Support/Claude")
        let memberships = Set(["claude-code-sessions", "local-agent-mode-sessions"].flatMap { directory in
            listDirectories(root.appendingPathComponent(directory).appendingPathComponent(user))
                .compactMap { UUID(uuidString: $0)?.uuidString.lowercased() }
        })
        var organizations = memberships
        if let activeOrganization { organizations.insert(activeOrganization) }
        if let text = try? desktop.files.readTextIfPresent(root.appendingPathComponent("config.json").path),
           let rootObject = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        {
            organizations.formUnion(rootObject.keys.compactMap {
                $0.split(separator: ":").last.flatMap { UUID(uuidString: String($0))?.uuidString.lowercased() }
            })
        }
        if let text = try? desktop.files.readTextIfPresent(
            root.appendingPathComponent("plan-usage-history.json").path
        ), let history = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
           let samples = history["samples"] as? [[String: Any]]
        {
            organizations.formUnion(samples.compactMap {
                ($0["org"] as? String).flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
            })
        }
        let cliOrganization = cliIdentity.flatMap { identity -> String? in
            let parts = identity.split(separator: "|")
            guard parts.count == 2,
                  String(parts[0]).caseInsensitiveCompare(user) == .orderedSame
            else { return nil }
            return String(parts[1]).lowercased()
        }

        return organizations.sorted { lhs, rhs in
            lhs == activeOrganization ? true : rhs == activeOrganization ? false : lhs < rhs
        }.compactMap { organization in
            guard memberships.contains(organization)
                || organization == activeOrganization || organization == cliOrganization
            else { return nil }
            let result = organization == activeOrganization ? active : desktop.load(
                allowInteraction: false, organization: organization, expectedAccountUUID: user
            )
            guard result.status == .available || result.status == .permissionRequired else { return nil }
            let plan = result.oauth?.subscriptionType?.lowercased()
            let label = plan.map { ["max", "pro", "free"].contains($0) } == true ? "Personal"
                : plan?.capitalized ?? "Organization \(organization.prefix(8))"
            return DesktopOrganization(id: organization, identityKey: "\(user)|\(organization)", label: label)
        }
    }
}
