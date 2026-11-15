#!/usr/bin/env bash
# Fetch the projektor release named in ./projektor.version into ./vendor.
#
# wrangler.jsonc names this as build.command, so every `wrangler deploy --config
# wrangler.jsonc` (the Deploy button's deploy step, CI's dry-run) fetches the release
# first. It only fetches: deploying from here re-ran this script through wrangler's
# own build step (PROJ-1073). cf-deploy.sh does the deploy, migrations and secret.
set -euo pipefail

REPO="${PROJEKTOR_REPO:-TAJD/projektor}"
VERSION="${PROJEKTOR_VERSION:-$(cat projektor.version 2>/dev/null || echo latest)}"

echo "==> Fetching projektor $VERSION from $REPO"
rm -rf vendor && mkdir -p vendor
if [ "$VERSION" = "latest" ]; then
	VERSION="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")"
	VERSION="${VERSION##*/}"
	echo "==> latest is $VERSION"
fi
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/projektor.tar.gz" "https://github.com/$REPO/releases/download/$VERSION/projektor-$VERSION.tar.gz"
tar -xzf "$TMP/projektor.tar.gz" -C vendor
rm -rf "$TMP"
