# Privacy & Usage Data

OpenUsage does not include an analytics or crash-reporting SDK. It does not send activity pings,
provider-refresh events, error reports, or crash reports to the OpenUsage maintainers.

## What is never shared

- No account details, names, emails, or credentials are sent to OpenUsage.
- No usage values, spend amounts, token counts, limits, error messages, or file paths are sent to
  OpenUsage.
- No anonymous install identifier or analytics preference is created.

## Credentials stored on this Mac

OpenUsage primarily reads credentials that provider tools already keep on your Mac. When it writes a
user-supplied API key or saves a refreshed credential, the file is replaced atomically and restricted to
your macOS account (owner read and write only). Antigravity's short-lived refreshed-token cache is tied
to the current Keychain login using a one-way fingerprint; the refresh credential itself is not copied.
The cache is never used after logout, an account change, or while Keychain access is unavailable.

Claude Desktop access is strictly read-only. OpenUsage may ask macOS for permission to use the
`Claude Safe Storage` Keychain item so it can decrypt Desktop's current access token. It never uses
Desktop's rotating refresh token and never modifies Desktop's config, cookies, or Keychain data.

## Network requests

OpenUsage calls provider APIs to retrieve the usage data shown in the app. It also fetches public
[model price lists](pricing.md) about once an hour from `raw.githubusercontent.com`, `models.dev`, and
this project's GitHub Pages. These price-list downloads carry no usage, log, or account information.
The spend tiles are computed from local CLI logs entirely on your Mac; no log data leaves it.

To avoid re-reading unchanged Claude, Codex, and pi logs after every relaunch, OpenUsage keeps parsed
usage events in `~/Library/Application Support/OpenUsage/log-scan-cache/`. These records contain the
usage metadata needed for local totals, including any per-event cost already recorded by a provider,
but not raw JSONL lines or conversation text. They are private to your macOS account and are never sent
to a provider or iCloud. Old source-file records are dropped as the scan window advances, and identity
caches that have not been used for 35 days are removed. Computed aggregates and totals are not persisted
in this cache.

If you explicitly turn on [iCloud Sync](icloud-sync.md), OpenUsage writes normalized daily tokens,
spend, and model totals to its private iCloud container so your own Macs can show one combined summary.
Credentials, account limits, provider responses, and raw logs are never written there. iCloud Sync is
off by default and uses your iCloud account.
