#!/usr/bin/env bash
# Deploy projektor from a pre-built release artifact. No source, no build step.
#
#   ./deploy.sh
#
# Works locally (wrangler OAuth via `wrangler login`) and in CI (CLOUDFLARE_API_TOKEN
# + CLOUDFLARE_ACCOUNT_ID env vars). Steps: download the pinned release, extract it
# into ./vendor, apply D1 migrations, deploy the Worker.
set -euo pipefail

# ── Config (override via env) ────────────────────────────────────────────────
REPO="${PROJEKTOR_REPO:-REPLACE_WITH_YOUR_GITHUB_USER/projektor}"
WRANGLER="${WRANGLER:-npx wrangler}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${PROJEKTOR_VERSION:-$(cat projektor.version 2>/dev/null || true)}"
: "${VERSION:?Set PROJEKTOR_VERSION or write a tag (e.g. v1.2.0) to ./projektor.version}"

echo "==> Fetching projektor $VERSION from $REPO"
rm -rf vendor && mkdir -p vendor
TMP="$(mktemp -d)"
gh release download "$VERSION" -R "$REPO" -p 'projektor-*.tar.gz' -D "$TMP"
tar -xzf "$TMP"/projektor-*.tar.gz -C vendor
rm -rf "$TMP"

# ── Bootstrap config on first run ────────────────────────────────────────────
if [ ! -f wrangler.toml ]; then
  cp vendor/wrangler.example.toml wrangler.toml
  echo ""
  echo "Created wrangler.toml from the release template."
  echo "Fill in the REPLACE_ values (D1 database_id, KV id, CF Access, ADMIN_EMAILS),"
  echo "then re-run ./deploy.sh"
  exit 1
fi

echo "==> Applying D1 migrations (remote)"
$WRANGLER d1 migrations apply projektor --remote --config wrangler.toml

echo "==> Deploying Worker"
$WRANGLER deploy --config wrangler.toml

echo ""
echo "==> Deployed projektor $VERSION"
