# Port plan: multi-account (+ per-account icons) → Swift OpenUsage

Branch: `swift-port` (worktree `~/DEV/openusage-swift`, based on upstream `v0.7.1-beta.1` Swift rewrite).
Goal: bring our Tauri fork's features (multiple accounts per provider, per-account label + custom icon,
add/edit/delete account UI) into the native Swift app.

## Why this is feasible
The Swift auth layer ALREADY parameterizes the credential source by config dir:
- `ClaudeAuthStore.claudeHomeOverride()` reads `CLAUDE_CONFIG_DIR` and hashes it into the keychain service
  (`Claude Code-credentials-<hash(dir)>`), with file fallback `<dir>/.credentials.json`.
- `CodexAuthStore.codexHome()` reads `CODEX_HOME` → `<dir>/auth.json`.
The ONLY blocker is that each provider is a singleton (`AppContainer.providers = [ClaudeProvider(), …]`)
with no per-account dimension. So: add an account dimension, parameterize the auth read by configDir
(not the global process env), instantiate one runtime per account, and key state/UI by account.

## Core design decisions (chosen — reused from our Tauri approach)
1. **Account id model:** default account `id == providerID` ("claude"); extra accounts `id = "claude#<n>"`.
   → Existing UserDefaults layouts (keyed "claude.*") keep working as the default account. **No migration churn.**
2. **Credential isolation:** thread `configDir: String?` as an explicit parameter through the auth stores
   (NOT the global process env — two accounts in one process can't share one env var). `nil` = default location.
3. **Per-account custom icon:** stored as a file under Application Support; referenced by path. Full-color in
   list/cards; rendered as a monochrome template `NSImage` in the menu bar.
4. **Label:** shown as "Claude · Work".
5. **Refresh:** one runtime per account, refreshed in parallel (independent credentials → no conflict).
6. **Enable/disable + ordering:** per account (keyed by account id).
7. **Default-account synthesis:** on launch, if a provider has no stored accounts, synthesize one default
   (id==providerID, configDir=nil). Existing users transparently get their current account as "default".

## Data model (new)
`Sources/OpenUsage/Models/ProviderAccount.swift`
```swift
struct ProviderAccount: Identifiable, Codable, Hashable {
    let id: String           // == providerID for default; "claude#1" for extras
    let providerID: String   // "claude"
    var label: String?       // "Work" (nil for default)
    var configDir: String?   // CLAUDE_CONFIG_DIR / CODEX_HOME; nil = default location
    var iconRelPath: String? // file under Application Support/AccountIcons; nil = provider default
}
```
`Sources/OpenUsage/Stores/AccountsStore.swift` (new, @Observable, UserDefaults key
`openusage.accounts.v1`): `accounts(for providerID) -> [ProviderAccount]`, add/update/remove,
synthesize default when empty. Maps account.id → ProviderAccount.

## Phased implementation

### Phase 0 — Foundation (no behavior change)
- Add `ProviderAccount` + `AccountsStore`. Synthesize default accounts. Persist. Unit test the store.
- Acceptance: app builds + runs identically (one default account per provider).

### Phase 1 — Parameterize the credential source by account
- `ClaudeAuthStore` / `CodexAuthStore`: accept `configDir: String?` explicitly (override the env lookup);
  keep env as fallback when nil. (Verify: keychain hashing + file paths use the passed dir.)
- `ClaudeProvider` / `CodexProvider`: take a `ProviderAccount` in init; expose `account`; use its configDir
  + present `provider.id`/displayName scoped to the account (id = account.id, name = "Claude · <label>").
- `ProviderRuntime`: add `var account: ProviderAccount { get }` (default-synthesizing for other providers).
- Acceptance: a ClaudeProvider built with configDir `~/CP/.claude` reads the work account; default reads default.

### Phase 2 — Instantiate one runtime per account
- `AppContainer`: build providers by flat-mapping accounts → runtimes (claude/codex multi; others single).
- `WidgetDataStore`: key snapshots/errors by **account id** (default id==providerID → existing keys intact).
- Refresh loop iterates account runtimes (parallel).
- Acceptance: two Claude accounts both fetch + store snapshots independently.

### Phase 3 — Enable/disable + ordering per account
- `ProviderEnablementStore`: key by account id.
- `LayoutStore`: provider order/groups become account-aware (account id is the grouping key; descriptor IDs
  for default account unchanged; extra accounts use `"<accountId>.<metric>"`).
- Acceptance: toggling/reordering the Work account is independent of Personal.

### Phase 4 — UI: list + menu bar
- `DashboardView` / `ProviderCard` / `ProviderSectionHeader`: one card per account; header shows
  "Claude · Work" + the account icon.
- `MenuBarContent` / `MenuBarStripRenderer`: groups per account; `IconSource` gains an account/custom-file
  case; menu-bar icon rendered as template (monochrome).
- Acceptance: two Claude cards + two menu-bar entries, visually distinct.

### Phase 5 — Settings: Add / Edit / Delete account
- `SettingsScreen`: under each multi-account-capable provider (claude, codex), list accounts with
  edit (pencil) + delete (trash); "Add account" button. Default account row keeps the enable toggle.
- New `AccountSettingsView`: label field; **folder picker** for config dir (NSOpenPanel /
  `.fileImporter`, with `showsHiddenFiles = true` since `.claude`/`.codex` are dotfolders); icon picker
  (choose file → copy into Application Support/AccountIcons; or "Default"). Save → AccountsStore.
- Acceptance: add a "CulturePulse" Claude account pointing at `~/CP/.claude`, pick an icon, see it appear.

### Phase 6 — Per-account custom icon rendering + polish
- Icon load/cache service; template rendering for menu bar; fallback to provider mark.
- Optional polish (only if the Swift app has the analogous issue): per-account refresh isolation,
  panel focus during native picker.
- Acceptance: custom icon shows full-color in the list and monochrome in the menu bar.

## Files (new / modified)
NEW: Models/ProviderAccount.swift · Stores/AccountsStore.swift · Views/AccountSettingsView.swift ·
Services/AccountIconStore.swift
MODIFY: Providers/ProviderRuntime.swift · Providers/Claude/{ClaudeProvider,ClaudeAuthStore}.swift ·
Providers/Codex/{CodexProvider,CodexAuthStore}.swift · App/AppContainer.swift ·
Stores/{WidgetDataStore,ProviderEnablementStore,LayoutStore}.swift ·
Views/{DashboardView,ProviderCard,ProviderSectionHeader,SettingsScreen}.swift ·
Models/MenuBarContent.swift · Support/{MenuBarStripRenderer,ProviderMarks/ProviderIconShape}.swift

## Risks / hard parts
- **LayoutStore descriptor IDs** are pervasive (placed widgets, metric order, pins). The id==providerID
  default trick avoids migration for existing users; extra accounts add new ids. Still the highest-touch area.
- **Custom icon persistence** (file storage + template rendering) is new surface.
- **Concurrency**: auth stores must be safe when N instances read different dirs concurrently (they're
  `Sendable` structs — good). Confirm no shared mutable global (e.g., a keychain run guard) collides.
- **Tests**: existing tests assume single instance per provider; add per-account fixtures.

## Build / test
`cd ~/DEV/openusage-swift && swift build` · `swift test` (Tests/OpenUsageTests). First build resolves SPM deps.

## Scope note
Items not ported (Tauri-infra specific, not app features): our self-hosted updater channel + Apple-signing
workflow (the Swift app has its own release/updater setup). This plan covers the user-facing features only.
