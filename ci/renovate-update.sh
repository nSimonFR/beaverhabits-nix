#!/usr/bin/env bash
# Recompute BeaverHabits' Nix src hash after Renovate bumps `version` in package.nix.
#
# Renovate's customManager rewrites the `version = "X.Y.Z"` string in package.nix,
# then runs this as a postUpgradeTask (arg $1 = the new version). uv2nix reads
# uv.lock straight from the source tree, so the ONLY hash that changes on a bump is
# the fetchFromGitHub src hash — recompute it with nurl (deterministic, no build).
# Requires nurl on PATH (the CI workflow installs it).
set -euo pipefail
cd "$(dirname "$0")/.."

ver="${1:-}"
if [ -z "$ver" ]; then
  ver=$(grep -oE 'version = "[^"]+"' package.nix | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
fi
echo ">> recomputing src hash for beaverhabits v$ver"

newsrc=$(nurl "https://github.com/daya0576/beaverhabits" "v$ver" 2>/dev/null \
           | grep -oE 'sha256-[A-Za-z0-9+/=]+' | head -1)
[ -n "$newsrc" ] || { echo "ERROR: nurl returned no src hash for v$ver"; exit 1; }

# package.nix carries exactly one sha256 literal (the rawSrc fetchFromGitHub), so
# a single global substitution is unambiguous.
sed -i -E "s#sha256-[A-Za-z0-9+/=]+#$newsrc#" package.nix
echo ">> src hash = $newsrc"
echo ">> hash recompute complete for beaverhabits v$ver"
