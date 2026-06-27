# Deploying projektor with an AI agent

This is the **zero-config** path: an AI agent (e.g. Claude Code) stands up a full
projektor instance on your Cloudflare account with no manual resource creation and
no copying of resource IDs. It relies on Cloudflare's
[automatic resource provisioning](https://developers.cloudflare.com/changelog/2025-10-24-automatic-resource-provisioning/)
(wrangler ≥ 4.45, open beta): a binding-only config means `wrangler deploy` creates
the D1 database, KV namespace, and R2 bucket for you and writes their IDs back.

> This deploys the **infrastructure** (Worker + D1 + KV + R2). Having the agent then
> *operate* projektor over MCP — create the first workspace, projects, issues, wiki —
> is the sibling flow (PROJ-200).

## What the agent needs

- Cloudflare auth — either `wrangler login` (interactive) **or**
  `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (headless). The token needs
  **Workers Scripts, D1, KV, R2 = Edit** and **Account Settings = Read**
  (the same scopes as `deploy.sh` — the common mistake is omitting D1).
- `gh` (to download the release artifact), `bash`, `tar`, `openssl`, and `wrangler ≥ 4.45`.

## The prompt

Point the agent at this repo and say:

> Deploy projektor to my Cloudflare account. Pin the latest release in
> `projektor.version`, then run `deploy-auto.sh` with `PROJEKTOR_REPO` set to my
> projektor repo and `ADMIN_EMAILS` set to my email. Report the deployed URL.

## What the agent runs

```bash
echo "v0.2.3" > projektor.version                 # pin a real release tag

PROJEKTOR_REPO=you/projektor \
ADMIN_EMAILS=you@example.com \
  ./deploy-auto.sh
```

`deploy-auto.sh` does, in order:

1. **Fetch** the pinned release artifact (`gh release download`) into `./vendor`.
2. **Generate** a binding-only `wrangler.toml` — D1/KV/R2 declared with **no IDs**
   (only created on first run, so re-runs never clobber written-back IDs).
3. **`wrangler deploy`** — Cloudflare provisions the missing D1/KV/R2, binds them,
   writes their IDs back into `wrangler.toml`, and deploys the Worker.
4. **`wrangler d1 migrations apply DB --remote`** — migrations run against the
   **binding** `DB`, so they work no matter what the database ends up named.
5. **`wrangler secret put JWT_SECRET`** — a random secret is generated and set once
   (skipped if one already exists; it persists across future deploys).

Re-running it (e.g. after a version bump) reuses the provisioned resources — only
step 1, 3, and 4 do meaningful work.

## After deploy

- The Worker is live and serving. **Browser login** additionally needs a Cloudflare
  Access application; set `CF_ACCESS_TEAM_DOMAIN` and `CF_ACCESS_AUDIENCE` (env or in
  `wrangler.toml`) and re-deploy. (These are read at request time, so the deploy and
  the API itself work without them.)
- To have the agent operate the instance over MCP, see the sibling flow (PROJ-200).

## How this differs from `deploy.sh`

| | `deploy.sh` (manual) | `deploy-auto.sh` (agent / zero-config) |
|---|---|---|
| Create D1/KV/R2 | you run `wrangler … create` | wrangler auto-provisions on deploy |
| Resource IDs | you paste them into `wrangler.toml` | written back automatically |
| wrangler version | any 4.x | **≥ 4.45** (provisioning beta) |
| Best for | CI with fixed, pre-created resources | a fresh account / an agent doing it all |
