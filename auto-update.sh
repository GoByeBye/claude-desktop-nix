#!/usr/bin/env bash
# One-shot auto-updater, meant to be run on a schedule (cron / systemd timer)
# from a machine on a normal IP — Anthropic's release endpoint is behind
# Cloudflare and 403s datacenter IPs, so this can't run on GitHub-hosted CI.
#
# It bumps package.nix to the latest release, verifies the package still builds,
# commits, and pushes to the current branch. No-op (exit 0, nothing pushed) when
# already on the latest version.
#
# Usage:
#   ./auto-update.sh            # bump, build, commit, push
#   ./auto-update.sh --no-push  # bump, build, commit — leave the push to you
#   ./auto-update.sh --no-git   # just bump package.nix (build only), no commit
set -euo pipefail

cd "$(dirname "$0")"

do_git=1
do_push=1
for arg in "$@"; do
  case "$arg" in
    --no-push) do_push=0 ;;
    --no-git)  do_git=0; do_push=0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log() { echo "[auto-update] $*"; }

# Refuse to run on a dirty tree so we never sweep unrelated edits into the
# update commit.
if [[ -n "$(git status --porcelain -- package.nix)" ]]; then
  echo "error: package.nix has uncommitted changes; aborting" >&2
  exit 1
fi

./update.sh

if git diff --quiet -- package.nix; then
  log "already on the latest version — nothing to do."
  exit 0
fi

new_version=$(sed -nE 's/^[[:space:]]*version = "([^"]+)";/\1/p' package.nix)
log "bumped to ${new_version} — verifying build..."
nix build .#claude-desktop -L

if [[ "$do_git" -eq 0 ]]; then
  log "built OK. Leaving package.nix modified (--no-git)."
  exit 0
fi

git add package.nix
git commit -m "claude-desktop: update to ${new_version}"
log "committed update to ${new_version}."

if [[ "$do_push" -eq 1 ]]; then
  git push
  log "pushed."
else
  log "skipping push (--no-push)."
fi
