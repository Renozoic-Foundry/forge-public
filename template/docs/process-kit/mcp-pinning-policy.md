# MCP Pinning and Integrity Policy

Last verified: 2026-04-17

## Why this policy exists

`template/.mcp.json.jinja` bootstraps two MCP servers (`context7` via npm, `fetch` via PyPI) and enables them by default in every FORGE-bootstrapped project. Without this policy, both packages would install from the registry at every session start using `@latest`/`-y auto-accept` — a single compromised upstream release would propagate instantly to the entire install base with user-level permissions.

This policy is FORGE's minimum supply-chain bar for **auto-enabled** MCP servers. MCP servers that an operator opts into manually (not bootstrapped by default) have different trust assumptions and are governed by the consumer project's own policies.

## Threat model this policy addresses

| Threat | Defended? | Mechanism |
|---|---|---|
| Upstream release becomes malicious *after* we pin | **Yes** | Version pin (can't auto-advance to the malicious release) |
| Registry compromise replaces a pinned version in-place (account takeover, tag republish) | **Yes** | Integrity hash verification (`npm ci` checks package tarball sha512 against `package-lock.json`; `pip --require-hashes` checks against `requirements.lock`) |
| Operator blindly bumps to latest without review | **Partial** | Bump-verification checklist (policy) — soft gate; requires operator discipline |
| Malicious release published *before* we pin (compromise-before-pin) | **No** | Accepted residual — Sigstore/provenance attestation verification is the next layer (deferred) |
| Transitive dependency drift | **Partial** | `npm ci` pins full transitive tree with hashes; pip lockfile includes transitive hashes. Drift only on regen without review. |
| Post-install scripts (npm `postinstall`) | **No** | Accepted residual — pin + hash does not inhibit postinstall execution. Integrity hash covers *what* is installed, not *what it does on install*. |

## What's pinned

| Package | Registry | Pinned Version | Rationale for this version |
|---|---|---|---|
| `@upstash/context7-mcp` | npm | `2.1.7` | 2.1.8 was published 2026-04-13 (4 days old at pin time); 2.1.7 (published 2026-04-06, 11 days old at pin time) is past the immediate post-release regression window. One release behind latest. |
| `mcp-server-fetch` | PyPI | `2025.4.7` | Current latest; naturally aged (over a year old at pin time — no newer release since). Slow release cadence. |

Hashes are stored in:
- `template/.mcp-lock/npm/package-lock.json` (sha512 integrity field per entry, full transitive tree)
- `template/.mcp-lock/python/requirements.lock` (sha256 `--hash=` lines per entry, full transitive tree)

## Per-package staleness thresholds

`/now` surfaces a one-line staleness advisory when a pin exceeds its threshold:

| Package | Threshold | Rationale |
|---|---|---|
| `@upstash/context7-mcp` | 60 days | Weekly release cadence. A stricter 30-day threshold would produce alert fatigue (monthly nag). 60 days = roughly 8 releases behind before surfacing. |
| `mcp-server-fetch` | 365 days | Slow release cadence (7 total releases; a year between recent ones). 180-day bumps would be noise. |

The threshold is measured from the `Last verified:` date at the top of this policy doc (not the package's release date). Bumping or re-verifying a pin requires updating `Last verified:`.

## Bump-verification checklist

**Before rotating any pin**, execute every step in order. Each step is a discrete decision point — do not batch.

### For `@upstash/context7-mcp`

- [ ] **Read upstream release notes** for every version between the current pin and the target — `https://github.com/upstash/context7/releases` (or the npm package's `homepage` field). Read the diff, not just the tagline.
- [ ] **CVE / security advisory scan** — check `https://github.com/advisories?query=%40upstash%2Fcontext7-mcp` and `npm audit` output for any reported vulnerabilities affecting the current or target version.
- [ ] **N-day aging** — the target version must be at least **14 days old** at bump time. Do not pin to versions released within the last two weeks (ongoing weekly cadence makes this aggressive enough).
- [ ] **Transitive review** — after regeneration, `git diff .mcp-lock/npm/package-lock.json` to see which transitive deps changed versions/hashes. Any major-version bump in a transitive dep warrants investigation.
- [ ] **Regenerate lockfile** with the command in [Regeneration commands](#regeneration-commands) below.
- [ ] **Update `Last verified:` at top of this doc** to today's date.

### For `mcp-server-fetch`

- [ ] **Read upstream release notes** — `https://github.com/modelcontextprotocol/servers/tree/main/src/fetch` (canonical MCP fetch server).
- [ ] **CVE / security advisory scan** — both for `mcp-server-fetch` and for the key transitives (`httpx`, `requests`, `markdownify`, `pydantic`, `mcp`).
- [ ] **N-day aging** — target version must be at least **7 days old** (slower cadence, lower aging bar is acceptable).
- [ ] **Transitive review** — same as context7; inspect the pip lockfile diff.
- [ ] **Regenerate lockfile** with the command below.
- [ ] **Update `Last verified:`** to today's date.

## Reviewing a lockfile-diff PR safely

Pinning lockfiles are themselves supply-chain artifacts. A malicious PR that changes integrity hashes is a direct attack vector. When reviewing a lockfile bump PR:

1. **Verify the target version exists on the registry** — click through to the registry page (npmjs.com / pypi.org) and confirm the version number, release date, and publisher match expectations.
2. **Verify the integrity hash matches the registry's** — for npm: `curl -s https://registry.npmjs.org/@upstash/context7-mcp/<version> | jq -r .dist.integrity` and compare to the value in the PR. For pip: `curl -s https://pypi.org/pypi/mcp-server-fetch/<version>/json | jq -r '.urls[].digests.sha256'` and compare to the `--hash=sha256:` lines in the PR.
3. **Treat a mismatch as a blocker** — do not merge. A hash mismatch means either the PR is wrong or the registry's claim differs from the PR. Either case requires investigation.
4. **Do not rely on PR-chain trust alone** — even a trusted contributor can be compromised. Hash verification against the registry is a second layer.

## Fallback: pinned version is yanked upstream

If a pinned version is yanked from the registry (maintainer removes it, registry takedown):

1. `npm ci` / `pip install --require-hashes` will fail with a 404.
2. `/now` surfaces a persistent notice.
3. Operator runs the **full bump-verification checklist** above to advance to the next safe version.
4. **Do not skip the checklist** under time pressure — a yanked version may signal an active compromise; pinning immediately to the next version without review trusts that the registry's state is clean.

## Fail-closed behavior

When integrity verification fails for any reason:

- **Hash mismatch** — `npm ci` / `pip install --require-hashes` exits non-zero. The MCP server does not activate. `/now` surfaces a persistent notice until the cause is resolved or the server is disabled via `/configure`.
- **Missing lockfile** — same behavior. `npm ci` cannot run without `package-lock.json`; pip errors on missing requirements file. Fail-closed.
- **Missing required tooling** — `npm` or `pip` not in PATH. `/now` surfaces tooling-missing notice. MCP server does not activate.
- **No unverified fallback exists.** There is no `if verification fails, fall back to npx -y @latest` path. Removing the lockfile or disabling the check requires explicit operator action via `/configure`.

## Regeneration commands

### npm (`@upstash/context7-mcp`)

```bash
cd template/.mcp-lock/npm
# Update package.json "dependencies" to the target version, then:
npm install --package-lock-only --no-audit --no-fund
# Verify:
python -c "import json; d = json.load(open('package-lock.json')); p = d['packages']['node_modules/@upstash/context7-mcp']; print(p['version'], p['integrity'][:24])"
```

### pip (`mcp-server-fetch`)

```bash
cd template/.mcp-lock/python
# Update requirements.in to the target version, then:
pip-compile --generate-hashes --output-file=requirements.lock --quiet requirements.in
# Verify:
grep -A 1 "mcp-server-fetch==" requirements.lock
```

Commit the regenerated lockfiles along with an update to this doc's `Last verified:` date.

## Minimum tooling versions

- **npm ≥ 7** — required for package-lock.json v3 integrity field. Older npm produces v1 lockfiles without integrity.
- **Python ≥ 3.10** — required by `mcp-server-fetch`.
- **pip ≥ 22.3** — required for modern `--require-hashes` enforcement behavior.

If any tool is missing or below the minimum version, MCP activation fails closed and `/now` surfaces a tooling-mismatch notice.
