# Deploying projektor with an AI agent

This is the **zero-config** path: an AI agent (e.g. Claude Code) stands up a full
projektor instance on your Cloudflare account with no manual resource creation and
no resource IDs anywhere. It relies on Cloudflare's
[automatic resource provisioning](https://developers.cloudflare.com/changelog/2025-10-24-automatic-resource-provisioning/):
a **binding-only** config (no IDs) means `wrangler deploy` creates the D1 database,
KV namespace, and R2 bucket by name, and wrangler then resolves them by binding on
every command — including `d1 migrations apply` — so you never paste an ID.

> **wrangler ≥ 4.103 required.** Provisioning itself landed earlier (4.45), but
> older wrangler (e.g. 4.66) provisions the resources and then fails at
> `d1 migrations apply` demanding a `database_id`, leaving a half-deployed instance.
> `deploy-auto.sh` enforces the floor. (Verified end-to-end on 4.105.)

> This deploys the **infrastructure** (Worker + D1 + KV + R2). Having the agent then
> *operate* projektor over MCP — create the first workspace, projects, issues, wiki —
> is the sibling flow (PROJ-200).

## What the agent needs

- Cloudflare auth — either `wrangler login` (interactive) **or**
  `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (headless). The token needs
  **Workers Scripts, D1, KV, R2 = Edit** and **Account Settings = Read**
  (the same scopes as `deploy.sh` — the common mistake is omitting D1).
- `gh` (to download the release artifact), `bash`, `tar`, `openssl`, and `wrangler ≥ 4.103`.

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
   (only created on first run, so re-runs preserve any edits you made).
3. **`wrangler deploy`** — Cloudflare provisions the missing D1/KV/R2 **by name**,
   binds them to the Worker, and deploys.
4. **`wrangler d1 migrations apply DB --remote`** — migrations run against the
   **binding** `DB`; wrangler resolves it by name, so no `database_id` is needed.
5. **`wrangler secret put JWT_SECRET`** — a random secret is generated and set once
   (skipped if one already exists; it persists across future deploys).

Re-running it (e.g. after a version bump) reuses the resources (wrangler matches
them by name) — only steps 1, 3, and 4 do meaningful work.

### Deploying a second / demo instance

Set `PROJEKTOR_NAME` to deploy onto an account that already runs projektor without
touching the existing resources — it names the Worker, D1 database, and R2 bucket
(`<name>` / `<name>` / `<name>-files`):

```bash
PROJEKTOR_NAME=projektor-demo PROJEKTOR_REPO=you/projektor \
ADMIN_EMAILS=you@example.com ./deploy-auto.sh
```

## After deploy

The Worker is live and serving, but no one can log in until you configure Cloudflare
Access. That — plus first login, minting a token, and connecting an agent over MCP —
is the human handoff: **see [CONFIGURE.md](./CONFIGURE.md)**.

(projektor has no production bootstrap endpoint by design, so this step is human-gated:
an agent provisions the infrastructure, a human configures access and mints the first
token, then the agent can operate it.)

## How this differs from `deploy.sh`

| | `deploy.sh` (manual) | `deploy-auto.sh` (agent / zero-config) |
|---|---|---|
| Create D1/KV/R2 | you run `wrangler … create` | wrangler auto-provisions on deploy |
| Resource IDs | you paste them into `wrangler.toml` | never needed (resolved by name) |
| wrangler version | any 4.x | **≥ 4.103** (provision + id-less migrations) |
| Best for | CI with fixed, pre-created resources | a fresh account / an agent doing it all |
