#!/usr/bin/env bash
# Reports the status of this fork relative to the upstream project it tracks:
#   - latest release of each repo
#   - latest default-branch commit + the conclusion of its most recent CI run
#   - how far the fork's default branch is ahead of / behind upstream's
#
# Output is Markdown, so it reads fine in a terminal AND renders in a GitHub Actions
# job summary (the workflow appends it to $GITHUB_STEP_SUMMARY). Requires `gh` auth
# (locally) or the built-in GITHUB_TOKEN (in CI); both repos' data is public.
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-robinebers/openusage}"
FORK_REPO="${FORK_REPO:-lubomir-dlhy/openusage}"

# Latest published release tag + date, or an em dash when the repo has no releases.
latest_release() {
  gh api "repos/$1/releases/latest" \
    --jq 'if .tag_name then "`\(.tag_name)`  (\(.published_at | split("T")[0]))" else "—" end' \
    2>/dev/null || echo "—"
}

# "sha · date · subject" for the tip of the repo's default branch.
head_commit() {
  local branch
  branch=$(gh api "repos/$1" --jq '.default_branch')
  gh api "repos/$1/commits/$branch" \
    --jq '"`\(.sha[0:7])` · \(.commit.committer.date | split("T")[0]) · \(.commit.message | split("\n")[0])"' \
    2>/dev/null || echo "—"
}

# An emoji for the most recent Actions run on the repo's default branch.
ci_status() {
  local branch state
  branch=$(gh api "repos/$1" --jq '.default_branch')
  state=$(gh api "repos/$1/actions/runs?branch=$branch&per_page=1" \
    --jq '(.workflow_runs[0].conclusion // .workflow_runs[0].status) // "none"' 2>/dev/null || echo "none")
  case "$state" in
    success)             echo "✅ passing" ;;
    failure|timed_out)   echo "❌ failing" ;;
    cancelled)           echo "⚪ cancelled" ;;
    in_progress|queued)  echo "🟡 running" ;;
    none)                echo "—" ;;
    *)                   echo "$state" ;;
  esac
}

# ahead_by / behind_by of the FORK's default branch vs UPSTREAM's, via the cross-repo
# compare API (base = upstream, head = fork). Prints "STATUS AHEAD BEHIND".
sync_delta() {
  local up_owner up_branch fork_owner fork_branch
  up_owner=${UPSTREAM_REPO%%/*}; up_branch=$(gh api "repos/$UPSTREAM_REPO" --jq '.default_branch')
  fork_owner=${FORK_REPO%%/*};   fork_branch=$(gh api "repos/$FORK_REPO" --jq '.default_branch')
  gh api "repos/$UPSTREAM_REPO/compare/$up_owner:$up_branch...$fork_owner:$fork_branch" \
    --jq '"\(.status) \(.ahead_by) \(.behind_by)"' 2>/dev/null || echo "unknown 0 0"
}

printf '## Upstream status\n\n'
printf '| | Upstream (`%s`) | Fork (`%s`) |\n' "$UPSTREAM_REPO" "$FORK_REPO"
printf '|---|---|---|\n'
printf '| Latest release | %s | %s |\n' "$(latest_release "$UPSTREAM_REPO")" "$(latest_release "$FORK_REPO")"
printf '| Default-branch tip | %s | %s |\n' "$(head_commit "$UPSTREAM_REPO")" "$(head_commit "$FORK_REPO")"
printf '| CI (latest run) | %s | %s |\n' "$(ci_status "$UPSTREAM_REPO")" "$(ci_status "$FORK_REPO")"
printf '\n'

read -r status ahead behind < <(sync_delta)
case "$status" in
  identical) verdict="✅ **Up to date** — the fork's default branch matches upstream." ;;
  ahead)     verdict="✅ **Ahead by $ahead** — the fork carries $ahead commit(s) upstream doesn't; nothing to pull." ;;
  behind)    verdict="⬇️ **Behind by $behind** — upstream has $behind new commit(s). Run the \`Sync upstream\` workflow." ;;
  diverged)  verdict="🔀 **Diverged** — fork ahead $ahead, behind $behind. \`Sync upstream\` will open a merge PR for the $behind upstream commit(s)." ;;
  *)         verdict="⚠️ Could not compute the sync delta (no shared history or API error)." ;;
esac
printf '**Sync:** %s\n' "$verdict"
