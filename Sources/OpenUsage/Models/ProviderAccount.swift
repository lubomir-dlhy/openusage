import Foundation

/// One account within a provider. A provider can hold multiple accounts (e.g. a personal and a work
/// Claude, or two Codex logins), each reading from its own credential source via a config directory
/// (`CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex).
///
/// The DEFAULT account uses `id == providerID`, so every existing per-provider key (layout, snapshots,
/// enablement, widget descriptor ids like `"claude.session"`) keeps working unchanged — no migration.
/// Extra accounts use ids of the form `"<providerID>#<n>"` (e.g. `"claude#1"`).
struct ProviderAccount: Identifiable, Codable, Hashable {
    /// Stable account id. Equals `providerID` for the default account; `"<providerID>#<n>"` for extras.
    let id: String
    /// The provider this account belongs to (e.g. `"claude"`).
    let providerID: String
    /// User-facing label (e.g. `"Work"`). `nil` for the default account.
    var label: String?
    /// Credential-source override: the value for `CLAUDE_CONFIG_DIR` / `CODEX_HOME`. `nil` = the
    /// provider's default location. May contain a leading `~` (expanded when used).
    var configDir: String?
    /// File name of a custom icon stored in the app's `Application Support/AccountIcons` directory.
    /// `nil` = use the provider's bundled mark.
    var iconFileName: String?
    /// Chart tint for this account ("RRGGBB"), shown in the Total Spend ring and legend.
    /// `nil` = automatic (the provider's brand color, or a stable fallback hue for extra accounts).
    var colorHex: String?

    /// True for the implicit default account (reads the provider's default credential location).
    var isDefault: Bool { id == providerID }

    /// Display name for an account, e.g. `"Claude"` (default) or `"Claude · Work"`.
    func displayName(providerDisplayName: String) -> String {
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return providerDisplayName
        }
        return "\(providerDisplayName) · \(label)"
    }

    /// The implicit default account for a provider.
    static func makeDefault(providerID: String) -> ProviderAccount {
        ProviderAccount(id: providerID, providerID: providerID, label: nil, configDir: nil, iconFileName: nil, colorHex: nil)
    }
}
