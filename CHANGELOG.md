# FORGE Changelog

Releases of the FORGE (Framework for Organized Reliable Gated Engineering) template.

This changelog follows [Semantic Versioning](https://semver.org) bound to three explicit surfaces per the FORGE versioning contract:
- **Surface 1** — `copier.yml` variable names/types
- **Surface 2** — Slash-command public contract (`Usage:` line, argument parsing, choice-block options)
- **Surface 3** — `.forge/templates/project-schema.yaml` (reserved; introduced in future release)

---

## v3.0.0 — 2026-06-30

**MAJOR bump — breaking changes; migration required.** The plugin-primary distribution pivot lands: FORGE now installs as a Claude Code plugin, with Copier reduced to project scaffolding. Three MAJOR drivers; aggregate MAJOR.

**Audit**: `ADR-501-v2.1.0-to-v3.0.0-audit.md` (private forge repo). Base resolved v2.1.0 → v3.0.0 via the Spec 505 Path C resolver (immutable tag graph; fail-loud).

**Signed payload**: the plugin payload is minisign-signed (key `6269A10FAAA740E1`). The detached `.minisig` carries the trusted comment `tier=forge-public version=3.0.0`. See the v3.0.0 GitHub Release notes for the pubkey, the out-of-band SHA-256 (`2820bebb…a187`), and `FORGE_PUBKEY_URL` / `FORGE_PUBKEY_SHA256` install-time verification.

### Breaking changes (MAJOR drivers)

| Spec | Surface | Breaking change | Migration |
|------|---------|-----------------|-----------|
| **489** | S1 / render | **Plugin-primary migration (headline).** The Copier render is shrunk to scaffolding-only; the rendered functional hooks are removed — the signed plugin is the sole enforcer. `copier update` no longer renders framework files (`.forge/bin`, `lib`, commands, agents); CLAUDE.md/AGENTS.md doctrine still renders. | Install the plugin (`claude plugin install ./` from a forge-public checkout). A tag-anchored deprecation window + rollback snapshot ship with the release. |
| **294** | S1 | `copier.yml` pins `_min_copier_version: 9.3.0` — consumers on older Copier are blocked at the next `copier update`. | `pip install -U copier` (≥ 9.3.0) before stoking. |
| **340** | S2 | `/close` auto-captures retro signals — the per-signal confirm/edit/skip prompt is removed with no opt-in. | None required; capture is automatic at close, curation moves to `/evolve`. |

### New features (since v2.1.0)

- **Install as a Claude Code plugin** — `claude plugin install ./` ships the command/agent/skill/hook surface, signed and verifiable (Specs 463, 487–491).
- **Hands-off chained delivery with a push safety gate** — `/implement` can flow spec→spec without an intervening `/close`, while every `git push` still raises an in-session approval prompt so the human stays the release authority (Specs 494–498).
- **Signal-based `/evolve`** — the Evolve Loop is admitted by accumulated signal thresholds rather than a fixed calendar (Spec 500).
- **`/consensus`** — structured multi-role review (Devil's Advocate, Maverick Thinker, Competitor, C-suite) on demand before committing to a spec (Spec 179).
- **`/signal-to-strategy`** — convert external research signals into scored, testable advantage hypotheses that feed the backlog (Spec 458).
- **`/reconcile`** — ingest work committed outside FORGE into the spec corpus (Spec 486).
- **Hardened release tooling** — `cut-release.sh` resolves the base from the immutable local+remote tag graph and fails loud instead of defaulting to v0.0.0 (Spec 505); PowerShell parity (Spec 515).

### Surface change — Spec 491 command/skill consolidation (MINOR, preserved invocation)

Spec 491 consolidated the command/skill duals to **skill-only**. The un-namespaced invocations (`/now`, `/implement`, `/consensus`, `/evolve`, etc.) are **unchanged**. Removed: the namespaced `/forge:<name>` alias forms for 13 names (`/forge:brainstorm`, `/forge:consensus`, `/forge:decision`, `/forge:dependency-audit`, `/forge:evolve`, `/forge:explore`, `/forge:insights`, `/forge:interview`, `/forge:matrix`, `/forge:note`, `/forge:revise`, `/forge:synthesize`, `/forge:trace`). If you call the `/forge:<name>` namespaced form in scripts/keybindings, switch to the un-namespaced `/name`.

### Updating from v2.1.0

```bash
pip install -U copier                       # 1. Copier >= 9.3.0 (Spec 294 pin)
git clone https://github.com/Renozoic-Foundry/forge-public.git
cd forge-public && claude plugin install ./ # 2. Install the FORGE plugin (Claude Code)
/forge stoke                                # 3. Update scaffolding; pass --allow-major for the v2.1.0 -> v3.0.0 MAJOR drift
```

Full per-spec window classification (485–500 + the v3.0.0 readiness cluster): see ADR-501 and the canonical audit doc.

---

## v2.1.0 — 2026-04-21

MINOR bump. Two new operator-facing Surface-2 choice blocks; zero breaking changes; no migration required.

**Audit**: `docs/decisions/ADR-NNN-v2.0.0-to-v2.1.0-audit.md` in the private forge repo. Consensus: 2 approve / 1 concern resolved via DA-grounded reclassification (Spec 303 PATCH→MINOR).

### New operator-facing surfaces (MINOR drivers)

| Spec | Surface | Change |
|------|---------|--------|
| 303 | Surface 2 | `/close` Step 2d+++ — consumer-propagation gate. When a closing spec links a doc from a template command file but the doc is not mirrored under `template/docs/` or whitelisted in `sync-to-public.sh`, `/close` renders a new choice block (`sync`/`whitelist`/`skip`) so the operator fixes the propagation gap before close. Violation-conditional rendering — normal `/close` runs see no UI change. |
| 291 (Phase 4) | Surface 2 | `/forge-bootstrap` — new Step 3b version disclosure. Resolves latest `forge-public` tag + main-HEAD commits-ahead before Copier runs; presents a 3-option choice block (`latest` tag / `main` branch / specific `tag <name>`) threaded through `copier copy --vcs-ref`. Default (install latest tag) is unchanged from v2.0.0. |
| 291 (Phase 4) | Surface 2 | `/forge stoke` — new Step 0a+ template drift + yank check. Semver-compares consumer `_commit` against latest `forge-public` tag: PATCH/MINOR drift → warn + proceed; MAJOR drift → **BLOCK** with surface-change pointer unless `--allow-major` flag passed. Also parses `CHANGELOG.md` `## Yanked Tags` section and warns consumers pinned to yanked tags. Graceful degradation when `gh` CLI is absent or network is unreachable. Introduces new optional `--allow-major` argument. |

### Notable PATCH changes

- **Spec 296** — `/forge stoke` Step 0b honors `.copier-answers.yml` module selections instead of `--defaults`. Eliminates false-positive "missing file" prompts for module-gated content.
- **Spec 300** — Specless-commit-guard regex refined (command-position-anchored; supports env-var prefix + wrapper keywords). Internal hook — no operator-visible change.
- **Spec 301** — `/consensus` documents a 3-round cap + aligned-concern → canonical Revise convention. Prompt-instruction policy; no argument contract change.

### Updating from v2.0.0

```bash
/forge stoke
```

PATCH/MINOR drift (v2.0.0 → v2.1.0) — warns and proceeds. No `--allow-major` needed.

### Scope note

Spec 291 Phases 2 (release policy + `cut-release.sh` tooling) and 3 (release-eligible signal wiring in `/close`, `/now`, `/evolve`) remain unimplemented. **v2.1.0 ships Phase 4 only (pilot-facing surface)**. The full Spec 291 deliverable is still pending; v2.1.0 was hand-cut from the Phase 1 consensus-approved audit.

---

## v2.0.0 — 2026-04-20

First post-v1.0.0 release. Four breaking changes across Surfaces 1 and 2 triggered a MAJOR bump per the FORGE versioning contract.

**Audit**: [ADR-295 v1.0.0→v2.0.0 audit](https://github.com/Renozoic-Foundry/forge/blob/main/docs/decisions/ADR-295-v1.0.0-to-v2.0.0-audit.md) (private-repo link; operators with forge/ access). Consensus: 3/3 approve (DA + CRO + CTO, all with surface-diff citations).

### Breaking changes (MAJOR drivers)

| Spec | Surface | Change | Migration |
|------|---------|--------|-----------|
| 205 | Surface 1 | `copier.yml` — `compliance_profile` variable removed | Lane B (safety-critical) compliance gates deferred from public release. All conditionals hardcode `"none"`. No consumer action required; existing `.copier-answers.yml` entries for `compliance_profile` are ignored. |
| 218 | Surface 2 | `/retro` command deleted | Use `/close` — signal capture is now embedded in the spec-close workflow (Step 6, "Signal Capture"). No standalone `/retro` invocation needed. |
| 263 | Surface 2 | `/bug` command deleted | Use `/note [bug] <description>` instead. The `[bug]` tag triggers severity classification + routing to an existing or new spec. |
| 266 | Surface 2 | `/onboarding` argument contract rewritten | Onboarding collapsed from 12 interactive stops to **2 interactions**. Defaults are accepted automatically; adjustments happen later via the new `/configure` command. Scripts relying on the old 12-step prompt sequence will break — adopt `/onboarding` followed by `/configure` as needed. |

### Additive changes (MINOR specs — non-breaking)

- **Spec 256** — `/close` Step 10: post-close context compaction hook (opt-in via `forge.context.optimization.level`)
- **Spec 258** — `/close` Review Brief: new `consensus` choice option (preserves existing `approve`/`reject`/`show`)
- **Spec 266** (companion) — new `/configure` command for post-onboarding stack selection
- **Spec 284** — `/configure` now displays pinned MCP package versions for visibility

### Notable PATCH changes (non-breaking)

- **Spec 290** — `copier.yml`: `author` and `harness_command` default values changed from placeholder strings (`"Your Name"`, `"# No harness configured..."`) to empty strings. Default-value change only; variable names and types unchanged.
- 20+ other PATCH-level specs (docs improvements, output polish, internal step additions). See [ADR-295](https://github.com/Renozoic-Foundry/forge/blob/main/docs/decisions/ADR-295-v1.0.0-to-v2.0.0-audit.md) for the full classification table.

### Updating from v1.0.0

**Option A — Fresh bootstrap** (recommended for new projects):
```bash
python -m copier copy gh:Renozoic-Foundry/forge-public . --vcs-ref v2.0.0 --defaults
```

**Option B — Update an existing v1.0.0 project** (once Spec 291's `/forge stoke` MAJOR-drift block ships):
```bash
# /forge stoke will block on a MAJOR drift by default; explicit --allow-major required
/forge stoke --allow-major
```

**Option C — Update before Spec 291 ships**:
```bash
# Manual Copier update; operator reviews the diff
python -m copier update
```

After updating, review the migration table above for any scripted workflows that depend on `/retro`, `/bug`, the 12-step `/onboarding`, or the `compliance_profile` Copier variable.

---

## v1.0.0 — 2026-04-11

Initial public release. See [commit `2e8de6a`](https://github.com/Renozoic-Foundry/forge-public/commit/2e8de6a).
