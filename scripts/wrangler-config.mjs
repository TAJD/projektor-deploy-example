#!/usr/bin/env node
// One source of truth for the deploy config: the wrangler.example.toml that ships inside
// every projektor release (vendor/wrangler.example.toml).
//
//   node scripts/wrangler-config.mjs generate --name projektor --admin-emails a@b.c > wrangler.toml
//     Writes a binding-only config (no resource IDs; wrangler provisions D1/KV/R2 by name).
//     CF_ACCESS_TEAM_DOMAIN / CF_ACCESS_AUDIENCE / AUTO_JOIN_ROLE are copied from the
//     environment when set, and left out otherwise.
//
//   node scripts/wrangler-config.mjs check wrangler.jsonc wrangler.demo.toml
//     Fails if a committed config is missing a binding, Durable Object, migration,
//     compatibility flag, cron or Worker-first route that the release template has.
//     wrangler.jsonc has to be committed (the Deploy button provisions from it before
//     any build step runs), so this is what stops it drifting from the release again.
import { readFileSync } from "node:fs";
import { parse as parseJsonc } from "jsonc-parser";
import { parse as parseToml, stringify as stringifyToml } from "smol-toml";

const TEMPLATE = process.env.WRANGLER_TEMPLATE ?? "vendor/wrangler.example.toml";

export function load(path) {
	const text = readFileSync(path, "utf8");
	if (path.endsWith(".toml")) return parseToml(text);
	const errors = [];
	const out = parseJsonc(text, errors, { allowTrailingComma: true });
	if (errors.length) throw new Error(`${path}: invalid JSONC (${errors.length} errors)`);
	return out;
}

const isPlaceholder = (v) => typeof v === "string" && v.startsWith("REPLACE_");

export function generate(template, { name, adminEmails, env = {} }) {
	const cfg = structuredClone(template);
	cfg.name = name;
	for (const db of cfg.d1_databases ?? []) {
		delete db.database_id;
		db.database_name = name;
	}
	for (const kv of cfg.kv_namespaces ?? []) delete kv.id;
	for (const r2 of cfg.r2_buckets ?? []) r2.bucket_name = `${name}-files`;

	const vars = { ...(cfg.vars ?? {}) };
	for (const [k, v] of Object.entries(vars)) if (isPlaceholder(v)) delete vars[k];
	// Invite-only unless the deployer opts in: only ADMIN_EMAILS become owners.
	delete vars.AUTO_JOIN_ROLE;
	vars.ADMIN_EMAILS = adminEmails;
	for (const k of ["CF_ACCESS_TEAM_DOMAIN", "CF_ACCESS_AUDIENCE", "AUTO_JOIN_ROLE"]) {
		if (env[k]) vars[k] = env[k];
	}
	cfg.vars = vars;
	return cfg;
}

const set = (xs) => new Set(xs ?? []);
const names = (xs, key = "binding") => (xs ?? []).map((x) => x[key]);

// Everything the release template requires; each entry is [label, required[], actual[]].
export function check(template, target) {
	const problems = [];
	const missing = (label, need, have) => {
		const h = set(have);
		const gone = [...set(need)].filter((x) => !h.has(x));
		if (gone.length) problems.push(`${label}: missing ${gone.join(", ")}`);
	};

	if ((target.compatibility_date ?? "") < template.compatibility_date) {
		problems.push(
			`compatibility_date: ${target.compatibility_date} is older than the release's ${template.compatibility_date}`
		);
	}
	for (const key of ["main"]) {
		if (target[key] !== template[key]) problems.push(`${key}: ${target[key]} != ${template[key]}`);
	}
	if (target.assets?.directory !== template.assets?.directory) {
		problems.push(`assets.directory: ${target.assets?.directory} != ${template.assets?.directory}`);
	}
	if (template.placement?.mode && target.placement?.mode !== template.placement.mode) {
		problems.push(`placement.mode: expected ${template.placement.mode}`);
	}
	missing("compatibility_flags", template.compatibility_flags, target.compatibility_flags);
	missing("assets.run_worker_first", template.assets?.run_worker_first, target.assets?.run_worker_first);
	missing("triggers.crons", template.triggers?.crons, target.triggers?.crons);
	missing("d1_databases", names(template.d1_databases), names(target.d1_databases));
	missing("kv_namespaces", names(template.kv_namespaces), names(target.kv_namespaces));
	missing("r2_buckets", names(template.r2_buckets), names(target.r2_buckets));
	missing(
		"durable_objects.bindings",
		(template.durable_objects?.bindings ?? []).map((b) => `${b.name}=${b.class_name}`),
		(target.durable_objects?.bindings ?? []).map((b) => `${b.name}=${b.class_name}`)
	);
	for (const db of template.d1_databases ?? []) {
		const t = (target.d1_databases ?? []).find((x) => x.binding === db.binding);
		if (t && t.migrations_dir !== db.migrations_dir) {
			problems.push(`d1_databases.${db.binding}.migrations_dir: ${t.migrations_dir} != ${db.migrations_dir}`);
		}
	}
	// Durable Object migrations apply in file order after the last deployed tag, so the
	// target must carry the template's tags as a prefix, in the same order.
	const want = (template.migrations ?? []).map((m) => `${m.tag}:${(m.new_sqlite_classes ?? []).join("+")}`);
	const have = (target.migrations ?? []).map((m) => `${m.tag}:${(m.new_sqlite_classes ?? []).join("+")}`);
	if (want.some((w, i) => have[i] !== w)) {
		problems.push(`migrations: expected [${want.join(", ")}], found [${have.join(", ")}]`);
	}
	return problems;
}

function arg(argv, flag) {
	const i = argv.indexOf(flag);
	return i >= 0 ? argv[i + 1] : undefined;
}

function main(argv) {
	const [cmd, ...rest] = argv;
	const template = load(TEMPLATE);
	if (cmd === "generate") {
		const name = arg(rest, "--name") ?? "projektor";
		const adminEmails = arg(rest, "--admin-emails");
		if (!adminEmails) throw new Error("--admin-emails is required");
		const cfg = generate(template, { name, adminEmails, env: process.env });
		process.stdout.write(
			"# Generated by deploy-auto.sh from the release's wrangler.example.toml.\n" +
				"# Binding-only: wrangler provisions D1/KV/R2 by name; no resource IDs needed.\n" +
				stringifyToml(cfg) +
				"\n"
		);
		return 0;
	}
	if (cmd === "check") {
		let failed = 0;
		for (const file of rest) {
			const problems = check(template, load(file));
			if (problems.length) {
				failed++;
				console.error(`✗ ${file} has drifted from ${TEMPLATE}:`);
				for (const p of problems) console.error(`    ${p}`);
			} else {
				console.log(`✓ ${file} matches ${TEMPLATE}`);
			}
		}
		return failed ? 1 : 0;
	}
	console.error("usage: wrangler-config.mjs generate --name N --admin-emails E | check FILE...");
	return 2;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main(process.argv.slice(2)));
