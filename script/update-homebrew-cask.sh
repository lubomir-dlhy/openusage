#!/usr/bin/env bash
set -euo pipefail

# Bumps the OpenUsage cask in the official Homebrew/homebrew-cask to a given version, by hand.
#
# This is the manual equivalent of the stable-only "Open bump PR against official Homebrew/homebrew-cask"
# step in .github/workflows/release.yml — use it for Phase 1 (the one-time corrective PR) or any time you
# need to bump the official cask outside CI. It computes the published DMG's sha256 and runs
# `brew bump-cask-pr`, which forks homebrew-cask, makes the edit, and opens the PR.
#
# It does NOT do Phase 1's structural rewrite for you: on the first run you must still hand-edit the
# scaffolded cask to match packaging/homebrew/Casks/openusage.rb (single universal url,
# depends_on macos: ">= :sequoia", com.robinebers.openusage zap paths, livecheck block). See
# packaging/homebrew/README.md → Rollout.
#
# Usage:
#   script/update-homebrew-cask.sh <version>        # e.g. 0.7.1 (version is required)
#
# Requires: brew, plus a GitHub token brew can use to fork/PR (HOMEBREW_GITHUB_API_TOKEN or `gh auth`).

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version>   (e.g. 0.7.1)" >&2; exit 1; }

REPO="robinebers/openusage"
DMG="OpenUsage-${VERSION}.dmg"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG}"

command -v brew >/dev/null || { echo "brew not found on PATH" >&2; exit 1; }

echo "==> computing sha256 for $URL"
# Stream the published release asset straight into shasum so we never keep the DMG around.
SHA256="$(curl -fsSL "$URL" | shasum -a 256 | awk '{print $1}')"
[ -n "$SHA256" ] || { echo "could not compute sha256 (is v${VERSION} published?)" >&2; exit 1; }
echo "    sha256: $SHA256"

echo "==> running brew bump-cask-pr for openusage ${VERSION}"
# --url is explicit so brew doesn't have to infer it from the (currently stale) cask. brew recomputes the
# sha256 from the asset itself; we print ours above only as a sanity check.
brew bump-cask-pr \
  --version "$VERSION" \
  --url "$URL" \
  --no-browse \
  openusage

echo "==> done — review the opened PR against Homebrew/homebrew-cask"
echo "    If this is the first (corrective) bump, hand-edit the cask body to match"
echo "    packaging/homebrew/Casks/openusage.rb before the PR is merged."
