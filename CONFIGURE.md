# After deploy: configure access and start using projektor

The deploy (see [AGENT-DEPLOY.md](./AGENT-DEPLOY.md) or [deploy.sh](./deploy.sh))
gives you a **live Worker with a migrated database** — but nobody can log in yet.
This is the human handoff: an agent can provision the infrastructure, but
**projektor has no production bootstrap endpoint by design** — the first login goes
through Cloudflare Access, and API tokens are minted from inside the app. So a human
configures access once, then you (or an agent) take it from there.

## 1. Put Cloudflare Access in front of it

projektor validates a **Cloudflare Access JWT** on every authenticated request, so
you must protect the Worker with Access before anyone can log in. Pick one:

**A. Quick — `*.workers.dev` (no custom domain)**
Workers & Pages → your Worker → **Settings → Domains & Routes → Enable Cloudflare
Access**, then **Manage Cloudflare Access** to set the authorized emails (include the
address you passed as `ADMIN_EMAILS`).

**B. Production — custom domain**
Add your domain as a Cloudflare zone, attach a **Custom Domain** to the Worker, then
**Zero Trust → Access → Applications → Add a self-hosted application** over that
hostname with a policy allowing your emails. (A self-hosted Access app requires a
hostname in a zone you own — which is why option A exists for workers.dev.)

Either way, collect the two values projektor needs:

| Value | Where to find it | projektor var |
|-------|------------------|---------------|
| **Team domain** | your Zero Trust org domain, e.g. `yourteam.cloudflareaccess.com` | `CF_ACCESS_TEAM_DOMAIN` |
| **AUD tag** | Access → Applications → your app → Overview → *Application Audience (AUD) Tag* | `CF_ACCESS_AUDIENCE` |

## 2. Wire Access into projektor and re-deploy

**If you have a local clone** (you ran `deploy.sh`/`deploy-auto.sh` yourself): add both
to your `wrangler.toml` `[vars]` and re-deploy:

```toml
[vars]
# ...existing vars...
CF_ACCESS_TEAM_DOMAIN = "yourteam.cloudflareaccess.com"
CF_ACCESS_AUDIENCE = "<your-aud-tag>"
```

```bash
PROJEKTOR_REPO=TAJD/projektor ADMIN_EMAILS=you@example.com ./deploy-auto.sh
```

> `deploy-auto.sh` won't overwrite an existing `wrangler.toml`, so edit it directly
> (or set `CF_ACCESS_TEAM_DOMAIN` + `CF_ACCESS_AUDIENCE` in the env and delete
> `wrangler.toml` to regenerate it with them). These vars are read at request time,
> so the API and static site already work without them — only login needs them.

**If you used the "Deploy to Cloudflare" one-click button**: you have no local
`wrangler.toml` - your config lives in `wrangler.jsonc` in the repo Cloudflare cloned
for you. Either:

- Set the vars directly on the Worker: **Workers & Pages → your Worker → Settings →
  Variables and Secrets → Add** for both `CF_ACCESS_TEAM_DOMAIN` and
  `CF_ACCESS_AUDIENCE`, then save (this redeploys automatically, no rebuild needed); or
- Clone the auto-created repo, add both vars to the `vars` block in `wrangler.jsonc`,
  commit, and push - Cloudflare Workers Builds picks up the push and redeploys.

## 3. First login → you become owner

Open `https://<your-host>/`. Cloudflare Access authenticates you; because your email
is in `ADMIN_EMAILS`, projektor makes you the **owner** and auto-creates the default
workspace (`DEFAULT_WORKSPACE_SLUG` / `DEFAULT_WORKSPACE_NAME`). Anyone else Access
admits is **invite-only** unless you opted into `AUTO_JOIN_ROLE`.

## 4. Mint a token and connect an agent

In the app: **Settings → Tokens**. Create a token (name + scopes, e.g. read/write —
owners/admins only). The token (prefixed `pk_`) is shown **once**, and right beside it
the page shows a ready-to-run **`claude mcp add` command with the token and workspace
already filled in** — copy that.

It looks like:

```bash
claude mcp add --transport http \
  --header "Authorization: Bearer pk_…" \
  --header "X-Workspace-Slug: <your-workspace-slug>" \
  projektor "https://<your-host>/mcp/<workspace-id>"
```

Run it, and the agent can create projects, issues, and wiki pages over MCP — the same
tools projektor's own development is tracked with.

## 5. Optional: route workspaces by subdomain

By default, every request must carry an `X-Workspace-Slug` header (the `claude mcp add`
command above, and the browser SPA, already do this for you). If you've provisioned real
workspace subdomains in DNS (e.g. `team.example.com` routes to the `team` workspace), you
can opt into resolving the workspace from the `Host` header's leading label instead:

```toml
[vars]
# ...existing vars...
WORKSPACE_SUBDOMAIN_ROUTING = "true"
```

Leave this unset for a single custom domain or the `*.workers.dev` default — there, the
`Host` header's leading label is a CDN/proxy artifact, not a real tenant signal, and
enabling this would misroute requests.

---

**The full path:** an agent provisions the infrastructure → a human configures Access
and mints a token → the agent (or human) operates it.
