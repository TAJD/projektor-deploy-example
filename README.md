# projektor deploy (example)

A minimal, config-only repo that deploys [projektor](https://github.com/TAJD/projektor)
to your own Cloudflare account. **No source code, no build step** — it downloads a
pre-built release artifact and deploys it with `wrangler`.

Three ways in, easiest first:

1. **One click** — the Deploy to Cloudflare button below. Cloudflare clones this repo
   into your account, provisions D1/KV/R2, and builds + deploys.
2. **One command / one prompt** — `./deploy-auto.sh` (or hand the repo to an AI agent);
   wrangler auto-provisions everything, no IDs to copy. See [AGENT-DEPLOY.md](./AGENT-DEPLOY.md).
3. **Manual / CI** — provision the resources yourself and deploy on every push. The flow
   further down.

After any of them, **configure Cloudflare Access** so you can log in — see [CONFIGURE.md](./CONFIGURE.md).

## Deploy with one click

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/TAJD/projektor-deploy-example)

Cloudflare reads [`wrangler.jsonc`](./wrangler.jsonc) (binding-only — no resource IDs),
provisions a D1 database, a KV namespace, and an R2 bucket, then runs
[`cf-build.sh`](./cf-build.sh): it downloads the pinned projektor release
(`projektor.version`), deploys the Worker, applies D1 migrations, and generates
`JWT_SECRET`. Fill in `ADMIN_EMAILS` on the setup page; that email becomes the owner
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
├── projektor.version             # the release you're pinned to (e.g. v1.2.0)
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
# Pin a version, then run deploy once to fetch the artifact + scaffold wrangler.toml:
echo "v1.0.0" > projektor.version          # use a real release tag
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

`deploy.yml` deploys the live `projektor-demo` instance (via the committed,
binding-only `wrangler.demo.toml`) on every push to `main`, then hits the
deployed URL and fails the job if it doesn't return 2xx. It also runs on PRs
against `main` — as a dry-run only, needing no Cloudflare auth — so it can be a
required check gating merges (branch ruleset on `main`). Configure these
**repository secrets** (Settings → Secrets and variables → Actions):

| Secret | How to get it |
|--------|---------------|
| `CLOUDFLARE_API_TOKEN` | **see the token recipe below — the common mistake is omitting D1** |
| `CLOUDFLARE_ACCOUNT_ID` | `wrangler whoami`, or the Cloudflare dashboard URL |
| `PROJEKTOR_RELEASE_PAT` | only if `projektor` is a **private** repo — a fine-grained PAT with `Contents: Read` on it, so CI can download the release. For a public projektor, delete this and let the workflow use the built-in token. |

To roll out a new projektor version: bump `projektor.version`, commit, push. CI deploys it.

If you deploy your own instance instead of using the demo config, point `deploy.yml`
at your own `wrangler.toml`/resource names, or adapt `deploy.sh`'s manual flow.

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
