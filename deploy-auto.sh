#!/usr/bin/env bash
# Agent / zero-config deploy of projektor.
#
#   PROJEKTOR_REPO=you/projektor ADMIN_EMAILS=you@example.com ./deploy-auto.sh
#
# Unlike ./deploy.sh, this needs NO manual `wrangler d1/kv/r2 create` and NO
# resource IDs anywhere. It writes a binding-only wrangler.toml (no IDs) and lets
# wrangler's automatic resource provisioning create the D1 database, KV namespace,
# and R2 bucket on first `deploy`. wrangler then resolves all three by binding /
# name on every command (deploy AND `d1 migrations apply`), so you never paste an
# ID. Verified on wrangler 4.105 (4.66 provisions fine but its `d1 migrations`
# still demands a database_id — hence the version floor below).
#
# This is the path an AI agent takes: "deploy projektor to my Cloudflare account."
#
# Auth: `wrangler login` (local) OR CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID
#       (CI / headless agent). The token needs the same scopes as deploy.sh —
#       Workers Scripts, D1, KV, R2 (Edit) + Account Settings (Read).
#
# Requires: wrangler >= 4.103 (this repo pins it), node, gh, bash, tar, openssl.
set -euo pipefail

# ── Config (override via env) ────────────────────────────────────────────────
REPO="${PROJEKTOR_REPO:-REPLACE_WITH_YOUR_GITHUB_USER/projektor}"
WRANGLER="${WRANGLER:-npx wrangler}"
# Worker + resource name. Override to stand up a second/demo instance on an
# account that already runs projektor (avoids clobbering existing resources).
NAME="${PROJEKTOR_NAME:-projektor}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${PROJEKTOR_VERSION:-$(cat projektor.version 2>/dev/null || true)}"
: "${VERSION:?Set PROJEKTOR_VERSION or write latest or a tag (e.g. v1.2.0) to ./projektor.version}"
: "${ADMIN_EMAILS:?Set ADMIN_EMAILS (comma-separated owner emails — first to log in owns the default workspace)}"

# ── Require a wrangler new enough to provision AND run id-less d1 migrations ──
# Older wranglers (e.g. 4.66) provision the resources but then fail at
# `d1 migrations apply` demanding a database_id, leaving a half-deployed instance.
MIN_WRANGLER="4.103.0"
WRANGLER_VER="$($WRANGLER --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [ -n "$WRANGLER_VER" ] && \
   [ "$(printf '%s\n%s\n' "$MIN_WRANGLER" "$WRANGLER_VER" | sort -V | head -1)" != "$MIN_WRANGLER" ]; then
  echo "ERROR: wrangler >= $MIN_WRANGLER required (found $WRANGLER_VER)." >&2
  echo "       Older versions provision resources but cannot apply D1 migrations without an ID." >&2
  exit 1
fi

echo "==> Fetching projektor $VERSION from $REPO"
rm -rf vendor && mkdir -p vendor
TMP="$(mktemp -d)"
# "latest" (the default in projektor.version) resolves to the newest release.
TAG="$VERSION"; [ "$VERSION" = "latest" ] && TAG=""
gh release download $TAG -R "$REPO" -p 'projektor-*.tar.gz' -D "$TMP"
tar -xzf "$TMP"/projektor-*.tar.gz -C vendor
rm -rf "$TMP"

# ── Generate a binding-only wrangler.toml on first run ───────────────────────
# Built from the release's own vendor/wrangler.example.toml, so every binding, Durable
# Object, compatibility flag and route the release needs is there. No resource IDs:
# wrangler provisions D1/KV/R2 by name on first `deploy`. Only created if absent, so a
# re-run keeps your edits (e.g. CF Access vars); delete it to regenerate after an upgrade
# (`node scripts/wrangler-config.mjs check wrangler.toml` tells you if you need to).
[ -d node_modules ] || npm install --no-audit --no-fund
if [ ! -f wrangler.toml ]; then
  echo "==> Writing binding-only wrangler.toml from vendor/wrangler.example.toml"
  node scripts/wrangler-config.mjs generate --name "$NAME" --admin-emails "$ADMIN_EMAILS" > wrangler.toml
else
  node scripts/wrangler-config.mjs check wrangler.toml || {
    echo "ERROR: wrangler.toml is missing config this release needs (see above)." >&2
    echo "       Delete it to regenerate, or add the missing entries by hand." >&2
    exit 1
  }
fi

# ── Deploy (auto-provisions any missing D1/KV/R2 by name) ────────────────────
echo "==> Deploying Worker (auto-provisions missing resources)"
$WRANGLER deploy --config wrangler.toml

# ── Apply D1 migrations by BINDING name (works regardless of DB name) ────────
echo "==> Applying D1 migrations (remote)"
$WRANGLER d1 migrations apply DB --remote --config wrangler.toml

# ── Set JWT_SECRET once (persists across deploys) ────────────────────────────
if ! $WRANGLER secret list --config wrangler.toml 2>/dev/null | grep -q '"JWT_SECRET"'; then
  echo "==> Setting JWT_SECRET (generated, set once)"
  openssl rand -hex 32 | $WRANGLER secret put JWT_SECRET --config wrangler.toml
fi

echo ""
echo "==> Deployed projektor $VERSION"
echo "    D1/KV/R2 were auto-provisioned by name; no resource IDs were needed."
if [ -z "${CF_ACCESS_TEAM_DOMAIN:-}" ]; then
  echo "    NOTE: CF Access is not configured — browser login will not work until you"
  echo "    set up a Cloudflare Access application and re-run with CF_ACCESS_TEAM_DOMAIN"
  echo "    and CF_ACCESS_AUDIENCE set (or add them to wrangler.toml and re-deploy)."
fi
