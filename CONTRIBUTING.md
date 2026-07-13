# Contributing / CI guardrails

This repo has a required GitHub Actions check and a branch ruleset on `main` -
here's what they do and where they fall short, so you don't have to reverse-engineer
it from workflow comments.

## What's enforced

- **Ruleset:** `main-require-deploy-check` (id `18812397`) on `main` requires the
  `Deploy to Cloudflare` job (`.github/workflows/deploy.yml`) to pass before a PR can
  merge.
- **On push to `main`:** the job deploys the live `projektor-demo` instance (via the
  committed `wrangler.demo.toml`), then hits the deployed URL and fails if it doesn't
  return 2xx. This is the real deploy + health check.
- **On a PR against `main`:** the same job runs as a **dry-run only** - it validates
  config and bindings (e.g. `wrangler.demo.toml` parses, required vars/secrets are
  present) without needing Cloudflare auth, so it can safely be a required check on
  forks and untrusted PRs too.

## Known limitation

The PR dry-run **cannot catch deploy-time failures** - a bad D1 migration, a
misconfigured health-check URL, or anything else that only breaks once `wrangler
deploy` actually talks to Cloudflare. Those only surface **after merge**, when the
push-to-main job runs the real deploy and health check. If that job fails, `main` is
left pointing at a version that didn't successfully deploy - fix forward with another
push, or revert.

In short: the required check is a floor (config sanity), not a ceiling (deploy
success). Don't take a green PR check as proof the merge will deploy cleanly.
