#!/usr/bin/env bash
# Auto-update package.nix to the latest Claude Desktop release.
#
# Resolves Anthropic's version-agnostic `latest/redirect` endpoint to the
# current versioned .deb, then rewrites `version`, the `Claude-<sha>.deb`
# filename in `url`, and `hash` in package.nix.
#
# Prints one of the following to stdout as the last line:
#   changed <old-version> <new-version>   — package.nix was updated
#   unchanged <version>                    — already on the latest version
#
# In GitHub Actions these are also written to $GITHUB_OUTPUT as
# `changed=true|false`, `old_version=`, `new_version=` for later steps.
set -euo pipefail

cd "$(dirname "$0")"

REDIRECT_URL="https://claude.ai/api/desktop/linux/x64/deb/latest/redirect"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
PKG="package.nix"

# The endpoint answers with a 307 whose Location header already holds the full
# versioned .deb URL, so we read that header directly instead of following the
# redirect to the CDN (avoids a needless ranged request that could also fail).
# claude.ai is behind Cloudflare; send a full browser-like header set and retry
# so a transient bot-score bump doesn't fail the run.
final_url=$(curl -fsS -A "$UA" --max-redirs 0 \
  -H 'Accept: */*' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Sec-Fetch-Dest: document' \
  -H 'Sec-Fetch-Mode: navigate' \
  -H 'Sec-Fetch-Site: none' \
  --retry 4 --retry-delay 5 --retry-all-errors \
  -D - -o /dev/null "$REDIRECT_URL" \
  | tr -d '\r' | sed -nE 's/^[Ll]ocation:[[:space:]]*(.+)$/\1/p' | head -n1)
if [[ "$final_url" != *"/Claude-"*.deb ]]; then
  echo "error: unexpected redirect target: '$final_url'" >&2
  exit 1
fi

new_version=$(printf '%s' "$final_url" | sed -nE 's#.*/x64/([^/]+)/[^/]+$#\1#p')
new_filename=$(basename "$final_url")
old_version=$(sed -nE 's/^[[:space:]]*version = "([^"]+)";/\1/p' "$PKG")

if [[ -z "$new_version" || -z "$new_filename" ]]; then
  echo "error: failed to parse version/filename from: $final_url" >&2
  exit 1
fi

# Constrain the parsed fields to their expected shapes. These values flow into
# package.nix and (via $GITHUB_OUTPUT) into workflow step inputs, so reject
# anything unexpected rather than propagate it.
if ! [[ "$new_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "error: unexpected version format: $new_version" >&2
  exit 1
fi
if ! [[ "$new_filename" =~ ^Claude-[0-9a-f]+\.deb$ ]]; then
  echo "error: unexpected filename format: $new_filename" >&2
  exit 1
fi

emit() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "changed=$1"
      echo "old_version=$old_version"
      echo "new_version=$new_version"
    } >>"$GITHUB_OUTPUT"
  fi
}

if [[ "$new_version" == "$old_version" ]]; then
  emit false
  echo "unchanged $old_version"
  exit 0
fi

echo "New release: $old_version -> $new_version ($new_filename)" >&2
echo "Fetching + hashing $final_url ..." >&2
# Extract the SRI hash from the --json output. The `sha256-` prefix is
# unambiguous (the storePath carries no such prefix), so grep avoids a jq dep.
new_hash=$(nix store prefetch-file --json "$final_url" \
  | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | head -n1)
if [[ "$new_hash" != sha256-* ]]; then
  echo "error: failed to compute hash (got: $new_hash)" >&2
  exit 1
fi

# Rewrite the three pinned fields. `version` is interpolated into `url`, so only
# the `Claude-<sha>.deb` filename needs replacing there.
sed -i -E \
  -e "s|^([[:space:]]*version = \")[^\"]*(\";)|\1${new_version}\2|" \
  -e "s|Claude-[0-9a-f]+\.deb|${new_filename}|" \
  -e "s|^([[:space:]]*hash = \")[^\"]*(\";)|\1${new_hash}\2|" \
  "$PKG"

emit true
echo "changed $old_version $new_version"
