import Foundation
import Observation

/// Source of truth for the accounts configured under each provider.
///
/// Only EXTRA (non-default) accounts are persisted, keyed by providerID. The default account
/// (`id == providerID`, default credential location) is implicit and synthesized on read — mirroring
/// `ProviderEnablementStore`'s "persist only the deviation" approach, so a fresh install and every
/// existing per-provider key keep working with zero migration.
@MainActor
@Observable
final class AccountsStore {
    private static let storageKey = "openusage.accounts.v1"

    /// Posted when the set of accounts changes, so the refresh loop / UI can react (parallels
    /// `ProviderEnablementStore.didChangeNotification`).
    nonisolated static let didChangeNotification = Notification.Name("AccountsDidChange")

    /// Persisted extra accounts only, keyed by providerID.
    private(set) var extraAccounts: [String: [ProviderAccount]]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.extraAccounts = Self.load(from: defaults)
    }

    /// All accounts for a provider: the implicit default first, then any user-added extras (in order).
    func accounts(for providerID: String) -> [ProviderAccount] {
        [.makeDefault(providerID: providerID)] + (extraAccounts[providerID] ?? [])
    }

    /// Resolve a single account by id. Ids without `"#"` are implicit defaults for that provider.
    func account(id: String) -> ProviderAccount? {
        if let hashIndex = id.firstIndex(of: "#") {
            let providerID = String(id[..<hashIndex])
            return extraAccounts[providerID]?.first { $0.id == id }
        }
        return .makeDefault(providerID: id) // id == providerID
    }

    /// Add a new extra account; returns the created account (with a freshly-allocated id).
    @discardableResult
    func addAccount(providerID: String, label: String?, configDir: String?, iconFileName: String? = nil)
        -> ProviderAccount
    {
        var list = extraAccounts[providerID] ?? []
        let account = ProviderAccount(
            id: nextID(providerID: providerID, existing: list),
            providerID: providerID,
            label: normalized(label),
            configDir: normalized(configDir),
            iconFileName: iconFileName
        )
        list.append(account)
        extraAccounts[providerID] = list
        persist()
        return account
    }

    /// Update an existing extra account (no-op for default accounts, which are not persisted).
    func updateAccount(_ account: ProviderAccount) {
        guard !account.isDefault, var list = extraAccounts[account.providerID],
              let idx = list.firstIndex(where: { $0.id == account.id })
        else { return }
        var updated = account
        updated.label = normalized(account.label)
        updated.configDir = normalized(account.configDir)
        list[idx] = updated
        extraAccounts[account.providerID] = list
        persist()
    }

    /// Remove an extra account by id (default accounts cannot be removed).
    func removeAccount(id: String) {
        guard let hashIndex = id.firstIndex(of: "#") else { return }
        let providerID = String(id[..<hashIndex])
        guard var list = extraAccounts[providerID], list.contains(where: { $0.id == id }) else { return }
        list.removeAll { $0.id == id }
        if list.isEmpty { extraAccounts[providerID] = nil } else { extraAccounts[providerID] = list }
        persist()
    }

    // MARK: - Private

    private func nextID(providerID: String, existing: [ProviderAccount]) -> String {
        let used = Set(existing.map(\.id))
        var n = 1
        while used.contains("\(providerID)#\(n)") { n += 1 }
        return "\(providerID)#\(n)"
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(extraAccounts) {
            defaults.set(data, forKey: Self.storageKey)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private static func load(from defaults: UserDefaults) -> [String: [ProviderAccount]] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [ProviderAccount]].self, from: data)
        else { return [:] }
        return decoded
    }
}
