#!/usr/bin/env bash
# Build command for the "Deploy to Cloudflare" button (Workers Builds).
#
# Referenced from wrangler.jsonc as  build.command = "bash ./cf-build.sh".
# Workers Builds runs this in Cloudflare's CI *after* it has provisioned the
# D1/KV/R2 resources declared in wrangler.jsonc, with wrangler already
# authenticated against the target account.
#
# projektor ships as a pre-built release artifact, not source — so the "build"
# is: download the pinned release, then bring up the instance fully (deploy,
# migrate, generate JWT_SECRET). We do the deploy here rather than leaning on
# Workers Builds' default `wrangler deploy` so that migrations and the secret
# run against an already-deployed Worker; the platform's own deploy step then
# re-runs `wrangler deploy`, which is idempotent.
#
# If this environment is NOT authenticated for wrangler (deploy/migrate fail),
# the one-click path can't complete — clone the repo and run ./deploy-auto.sh
# locally instead (same result, your own `wrangler login`).
set -euo pipefail

# Re-entry guard (PROJ-1073). wrangler.jsonc names this script as build.command, so the
# `wrangler deploy` below runs it again, and that run would deploy again, and so on: the
# one-click deploy recursed until it failed. The nested run has nothing to do.
if [ -n "${PROJEKTOR_CF_BUILD_ACTIVE:-}" ]; then
	exit 0
fi
export PROJEKTOR_CF_BUILD_ACTIVE=1

REPO="${PROJEKTOR_REPO:-TAJD/projektor}"
WRANGLER="${WRANGLER:-npx wrangler}"
VERSION="${PROJEKTOR_VERSION:-$(cat projektor.version 2>/dev/null || echo latest)}"

echo "==> Fetching projektor $VERSION from $REPO"
rm -rf vendor && mkdir -p vendor
if [ "$VERSION" = "latest" ]; then
	URL="https://github.com/$REPO/releases/latest/download/projektor-*.tar.gz"
	# 'latest' has no fixed filename, so resolve the asset via the API.
	ASSET="$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
		| grep -oE '"browser_download_url": *"[^"]*projektor-[^"]*\.tar\.gz"' \
		| head -1 | sed -E 's/.*"(https[^"]*)".*/\1/')"
	: "${ASSET:?could not resolve latest release asset URL}"
else
	ASSET="https://github.com/$REPO/releases/download/$VERSION/projektor-$VERSION.tar.gz"
fi
curl -fsSL -o /tmp/projektor.tar.gz "$ASSET"
tar -xzf /tmp/projektor.tar.gz -C vendor

# CI dry-runs this config without Cloudflare credentials: fetch the release only.
if [ -n "${PROJEKTOR_FETCH_ONLY:-}" ]; then
	echo "==> PROJEKTOR_FETCH_ONLY set: release fetched, not deploying"
	exit 0
fi

echo "==> Deploying Worker (binds the resources Cloudflare provisioned)"
$WRANGLER deploy --config wrangler.jsonc

echo "==> Applying D1 migrations (remote)"
$WRANGLER d1 migrations apply DB --remote --config wrangler.jsonc

if ! $WRANGLER secret list --config wrangler.jsonc 2>/dev/null | grep -q '"JWT_SECRET"'; then
	echo "==> Setting JWT_SECRET (generated once)"
	openssl rand -hex 32 | $WRANGLER secret put JWT_SECRET --config wrangler.jsonc
fi

echo ""
echo "==> projektor $VERSION is deployed."
echo "    Next: configure Cloudflare Access so you can log in — see CONFIGURE.md."
