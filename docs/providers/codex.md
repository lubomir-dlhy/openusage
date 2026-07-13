# Codex

Tracks your ChatGPT/Codex subscription limits using the login from the Codex CLI.

## What it tracks

| Metric | Meaning |
|---|---|
| Session | 5-hour rolling window usage |
| Weekly | 7-day window usage |
| Spark / Spark Weekly | GPT-5.3-Codex-Spark model limits — a 5-hour and a weekly window. Shown only when your account has the limit (otherwise "No data"), and tucked below the "show more" caret by default |
| Rate Limit Resets | On-demand rate-limit reset credits, shown as a count (e.g. `2 available`) with a colored dot for the soonest expiry; hover the value for a timeline of each credit's expiry |
| Extra Usage | Flex credits, shown verbatim as dollars + credits (e.g. `$31.84 · 796 credits`) |
| Today / Yesterday / Last 30 Days | Local spend, as cost, tokens, or both (see below) |

The Session and Weekly meters match each reported rate-limit window by its **duration**, not by the slot it arrives in — so a plan that only has a weekly limit (the ChatGPT profile shows a single "Weekly usage limit") shows just the Weekly row, and Session reads "No data". The same goes for Spark's windows.

When Codex reports your plan name, OpenUsage shows it beside the provider name.

## Where credentials come from

Sign in once with the Codex CLI (`codex`); OpenUsage reads the same auth files (`$CODEX_HOME` respected) with a keychain fallback. Tokens refresh automatically and rotate back into the auth file.

## The spend tiles

Today / Yesterday / Last 30 Days start from the Codex CLI's session rollouts, read **locally** under `~/.codex/sessions/` and `archived_sessions/` (or `$CODEX_HOME`) — no external tools needed. Days are grouped in your Mac's local time zone, so they line up with your own calendar. Each period is one tile showing cost and tokens together (`$4.08 · 1.2M tokens`); a day with no usage reads **No data** rather than a misleading `$0.00 · 0 tokens` — the same as every other spend-tracking provider. The live Session and Weekly meters are unaffected. The dollars are estimated from token counts at API rates (that's the ⓘ) using the shared [model pricing](../pricing.md); if your `config.toml` requests the fast/priority service tier, the fast rates apply. No log data leaves your Mac.

On top of the local logs, the tiles also count your usage on the surfaces those logs can't see — the Codex desktop app, the web, and cloud tasks — estimated from ChatGPT's cloud analytics the same way the Usage Trend does (see below). The estimated share rides in each tile's hover breakdown as its own **ChatGPT Cloud** row, so the measured local models and the estimated cloud usage stay distinguishable; its dollars use the same blended rate your local usage priced at. If the analytics call fails or there's nothing to calibrate from, the tiles quietly stay local-only.

## The Usage Trend

The Usage Trend merges two sources into one bar per day. The base is the same local session logs the spend tiles use — measured token counts. On top of that, OpenUsage asks ChatGPT's cloud analytics how much you used across **all** surfaces (CLI, the Codex desktop app, the web, cloud tasks). That API only reports usage as a percentage of your plan's credits, not tokens, so OpenUsage converts it: on days where your local logs and the analytics' "CLI" number overlap, it works out how many credits a token costs you, then uses that rate to estimate tokens for the non-CLI surfaces. Hovering a day with cloud activity shows both halves — the measured local tokens and the estimated cloud tokens (`≈485M tokens · 412M local + ~73M cloud (est.)`).

Because it's a calibration, the cloud half is an estimate: it drifts with the mix of models you use, and it assumes this Mac is where your CLI usage happens. If the analytics call fails, or there's no overlap to calibrate from (say, you never use the CLI), the trend — and the spend tiles' cloud share — quietly stay local-only, exactly what they showed before.

## Troubleshooting

- **"Not logged in"** — run `codex` and sign in, then refresh.
- **API-key-only setups** can't read subscription usage — sign in with your ChatGPT account instead.
- **Spend tiles show "No data"** — OpenUsage found no Codex session logs in the last 30 days. If your Codex home lives somewhere custom, set `CODEX_HOME` so both the Codex CLI and OpenUsage look in the same place.

## Under the hood

`GET https://chatgpt.com/backend-api/wham/usage` with the Codex OAuth token; refresh via `auth.openai.com`. A 401/403 triggers one token refresh and retry. Session and Weekly are read from the usage windows in that response, with the response headers used only when the window fields are missing. Each window's `limit_window_seconds` decides which meter it feeds (a day or longer → Weekly), because some plans report their only — weekly — window in the slot that historically carried the 5-hour one.

Spark and Spark Weekly come from the same response's `additional_rate_limits` array — model-specific limits that reuse the Session/Weekly window shape. OpenUsage surfaces the entry whose name identifies GPT-5.3-Codex-Spark as those two meters; accounts without the limit simply omit the entry, so the rows read "No data". Other model limits in that array aren't shown.

OpenUsage preserves Codex's reported `used_percent` verbatim. If the API reports 1% used for an untouched window, the app shows 99% left; if it reports 0%, the app shows 100% left. Codex rows use the normal reset label rather than inferring a special "Not started" state. Burn-rate pacing still waits until enough of the window has elapsed to make a useful projection.

The cloud half of the Usage Trend and the spend tiles comes from a best-effort `GET https://chatgpt.com/backend-api/wham/usage/daily-token-usage-breakdown` call (the same API the Codex analytics page uses), summing each day's per-surface credit percentages. The `cli` surface calibrates credits-per-token against the local logs; the remaining surfaces impute tokens at that rate, and the tiles price those tokens at the local window's blended $/token rate. Any failure — or no overlap to calibrate from — leaves the trend and tiles local-only.

The "Rate Limit Resets" row shows the on-demand reset-credit count, e.g. `2 available`, with a colored dot for the soonest credit's expiry — blue beyond a week, yellow within a week, red within 48 hours. OpenUsage also makes a best-effort `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` call — the dedicated endpoint that lists each credit's expiry — and surfaces those in a popover when you hover the value: a timeline of each reset, soonest-first — a numbered color dot, the exact expiry time (`Jul 12 at 5:30 PM`), and the countdown to it (`12d 18h`) on the trailing edge. When no credits are available it reads `0 available` and the popover shows `You have no rate limit resets`. If the dedicated call fails, the row falls back to the count embedded in the usage body (`rate_limit_reset_credits.available_count`); since that body carries no per-credit expiries, the popover states the count (`N available`) and notes that expiry times are unavailable rather than implying there are none.

### Using a reset from the popover

You can also spend a reset credit right from that popover — the same claim the Codex CLI's "Usage limit resets" picker performs. Hover a credit in the timeline and a **Use** button appears; clicking it expands that credit into an inline confirmation ("Immediately reset your usage limits. This can't be undone.") with **Reset** / **Cancel**. Confirming claims that exact credit and immediately resets your 5-hour and weekly windows; the app then refreshes Codex so the meters and the remaining count reflect it before the success line ("Reset claimed. Enjoy!") appears.

Safeguards, because a claim is irreversible:

- Claiming is always a deliberate two-click flow behind the hover popover — nothing is ever claimed automatically.
- Each claim targets one explicit credit (re-matched against a fresh credit list at claim time) and carries an idempotency key, so a retry after a network error can never spend a second credit.
- If the credit was meanwhile used elsewhere (CLI or web) the popover says it's no longer available and refreshes; if your usage doesn't need a reset, Codex refuses without spending the credit and the popover says so. After a claim resets usage, the remaining Use buttons disable ("nothing to reset") until the popover is reopened.
