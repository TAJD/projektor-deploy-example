#!/usr/bin/env bash
set -euo pipefail

WRANGLER="${WRANGLER:-npx wrangler}"
CONFIG="${CONFIG:-wrangler.jsonc}"

echo "==> Deploying Worker"
$WRANGLER deploy --config "$CONFIG"

echo "==> Applying D1 migrations (remote)"
$WRANGLER d1 migrations apply DB --remote --config "$CONFIG"

if ! $WRANGLER secret list --config "$CONFIG" 2>/dev/null | grep -q '"JWT_SECRET"'; then
	echo "==> Setting JWT_SECRET (generated once)"
	node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))" \
		| $WRANGLER secret put JWT_SECRET --config "$CONFIG"
fi

echo ""
echo "==> projektor is deployed."
echo "    Next: configure Cloudflare Access so you can log in — see CONFIGURE.md."
