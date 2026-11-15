# projektor deploy (example)

A minimal, config-only repo that deploys [projektor](https://github.com/TAJD/projektor)
to your own Cloudflare account. **No source code, no build step** — it downloads a
pre-built release artifact and deploys it with `wrangler`.

Want to see it running first? Check out the
[live demo](https://projektor-demo.tajdickson.workers.dev).

Three ways in, easiest first:

1. **One click** — the Deploy to Cloudflare button below. Cloudflare clones this repo
   into your account, provisions D1/KV/R2, and downloads + deploys the release artifact
   (no build step).
2. **One command / one prompt** — `./deploy-auto.sh` (or hand the repo to an AI agent);
   wrangler auto-provisions everything, no IDs to copy. See [AGENT-DEPLOY.md](./AGENT-DEPLOY.md).
3. **Manual / CI** — provision the resources yourself and deploy on every push. The flow
   further down.

After any of them, **configure Cloudflare Access** so you can log in — see [CONFIGURE.md](./CONFIGURE.md).

## Deploy with one click

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/TAJD/projektor-deploy-example)

Cloudflare reads [`wrangler.jsonc`](./wrangler.jsonc) (binding-only — no resource IDs),
provisions a D1 database, two KV namespaces (cache and OAuth), an R2 bucket and the
rate-limiter Durable Object, then runs `npm run deploy` ([`cf-deploy.sh`](./cf-deploy.sh)):
it deploys the Worker (whose build step, [`cf-build.sh`](./cf-build.sh), downloads the
projektor release named in `projektor.version`, `latest` by default), applies D1
migrations, and generates `JWT_SECRET`. Fill in `ADMIN_EMAILS` on the setup page; that email becomes the owner
once you log in.

> The one-click build needs wrangler to be authenticated in Cloudflare's build
> environment (Workers Builds provides this). If the build step can't deploy/migrate,
> use the equivalent local path instead: clone this repo and run `./deploy-auto.sh`.

```
this repo
├── deploy.sh                     # fetch release → migrate → deploy (local or CI)
├── deploy-auto.sh                # zero-config: auto-provision D1/KV/R2 (agent path)
├── AGENT-DEPLOY.md               # how an AI agent deploys with auto-provisioning
├── CONFIGURE.md                  # after deploy: set up Access, log in, connect an agent
├── projektor.version             # "latest", or a release tag to pin (e.g. v1.2.0)
├── scripts/wrangler-config.mjs   # generate wrangler.toml / check configs against the release
├── wrangler.toml.example         # illustrative config (the authoritative copy
│                                 #   ships inside each release as wrangler.example.toml)
├── wrangler.toml                 # YOUR config — created on first deploy, fill in IDs (gitignored)
├── wrangler.demo.toml            # committed, binding-only config CI deploys to projektor-demo
├── package.json                  # pins wrangler
├── vendor/                       # extracted release artifact (gitignored)
└── .github/workflows/deploy.yml  # automatic deploy on push to main
```

## What a release artifact contains

`projektor-<version>.tar.gz`, extracted into `vendor/`:

| Path | What |
|------|------|
| `vendor/worker.js` | the whole Worker, bundled and self-contained (no node_modules needed) |
| `vendor/web/` | the pre-built frontend (served as static assets) |
| `vendor/migrations/` | D1 migrations |
| `vendor/wrangler.example.toml` | the config template |
| `vendor/VERSION` | the version string |

---

## One-time setup

### 1. Provision Cloudflare resources

```bash
wrangler d1 create projektor
wrangler kv namespace create projektor
wrangler r2 bucket create projektor-files
```

### 2. Create your config

```bash
# projektor.version defaults to "latest"; to pin, write a tag instead:
gh release list -R TAJD/projektor          # find a real tag
echo "v0.11.1" > projektor.version         # optional: pin whichever tag you picked
PROJEKTOR_REPO=REPLACE_WITH_YOUR_GITHUB_USER/projektor ./deploy.sh
# -> creates wrangler.toml from the template; edit it and fill the REPLACE_ values
#    (D1 database_id, KV id, CF Access domain/audience, ADMIN_EMAILS), then re-run.
```

### 3. Set the Worker's one runtime secret (persists across deploys)

```bash
wrangler secret put JWT_SECRET    # any long random string; set once
```

### 4. Deploy

```bash
PROJEKTOR_REPO=REPLACE_WITH_YOUR_GITHUB_USER/projektor ./deploy.sh
```

---

## Automatic deploys (GitHub Actions)

`deploy.yml` checks the configs against the release and dry-runs them on every PR,
push and day. It **deploys only if you opt in**: set the repository *variables*
`DEPLOY_CONFIG` (a committed, binding-only wrangler config for your instance, e.g. a
copy of `wrangler.demo.toml` with your names) and `DEPLOY_URL` (health-checked after
deploy; the job fails if it doesn't return 2xx). This repo sets neither: the public
demo is deployed elsewhere. The PR run needs no Cloudflare auth, so it can be a
required check gating merges (branch ruleset on `main`; see
[CONTRIBUTING.md](./CONTRIBUTING.md) for what that ruleset does and its known
limitation). Configure these **repository secrets** (Settings → Secrets and
variables → Actions) when you opt in:

| Secret | How to get it |
|--------|---------------|
| `CLOUDFLARE_API_TOKEN` | **see the token recipe below — the common mistake is omitting D1** |
| `CLOUDFLARE_ACCOUNT_ID` | `wrangler whoami`, or the Cloudflare dashboard URL |
| `PROJEKTOR_RELEASE_PAT` | only if `projektor` is a **private** repo — a fine-grained PAT with `Contents: Read` on it, so CI can download the release. For a public projektor, delete this and let the workflow use the built-in token. |

To roll out a new projektor version: with `latest`, re-run the workflow; with a pinned tag,
bump `projektor.version`, commit, push. CI deploys it. CI also checks `wrangler.jsonc` and
`wrangler.demo.toml` against the release's `wrangler.example.toml` on every PR and daily,
so a release that needs new config fails here before a one-click user hits it.

If you deploy your own instance instead of using the demo config, `deploy.yml` won't
work as-is: `wrangler.toml` is gitignored by design (it holds your resource IDs), so CI
has nothing to deploy from on a fresh checkout. Either commit your own binding-only
toml — mirroring `wrangler.demo.toml` — and point `deploy.yml` at it, or skip the
GitHub Actions path entirely and use `deploy.sh`'s manual flow locally.

### The Cloudflare API token (get this right)

Do **not** use the built-in "Edit Cloudflare Workers" template — it omits D1, so
`wrangler deploy` succeeds but `d1 migrations apply` fails. Create a **Custom Token**
(My Profile → API Tokens → Create Token → Create Custom Token) with:

| Type | Permission | Access |
|------|-----------|--------|
| Account | Workers Scripts | Edit |
| Account | **D1** | **Edit** |
| Account | Workers KV Storage | Edit |
| Account | Workers R2 Storage | Edit |
| Account | Account Settings | Read |

- **Account Resources:** Include → your account.
- **Zone Resources:** none needed if you serve on `*.workers.dev`. Only add
  `Zone → Workers Routes → Edit` if you use a custom domain.

Verify the token before trusting CI:

```bash
CLOUDFLARE_API_TOKEN=xxx CLOUDFLARE_ACCOUNT_ID=yyy wrangler d1 list   # must succeed
```

If `d1 list` fails, the token is missing the D1 permission.

---

## Requirements

- [`wrangler`](https://developers.cloudflare.com/workers/wrangler/) (pinned in `package.json`; `npm install` then it's available via `npx`)
- [`gh`](https://cli.github.com/) (GitHub CLI) — to download the release artifact
- `bash`, `tar`
