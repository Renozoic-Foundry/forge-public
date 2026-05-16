# `scripts/` Propagation Policy

Last updated: 2026-05-09

This document defines which files under canonical `scripts/` propagate into `template/scripts/` (and from there into Copier-rendered consumer projects) versus which remain framework-internal (canonical-only). It is the single reference for the canonical-vs-template split and the criteria that drive the classification.

This is a meta-policy doc — it describes the propagation rules themselves and is therefore canonical-only (no `template/` mirror).

Authored under Spec 393. Validator enforcement is intentionally deferred — see [Deferred Validator Enforcement](#deferred-validator-enforcement) below.

## Why the split exists

FORGE develops itself **and** ships a Copier template that bootstraps consumer projects. The two contexts have different tooling needs:

- **Framework-time** scripts operate on FORGE's own dev artifacts: release tooling, public-mirror sync, audit-time validation of canonical-only files (e.g., `docs/specs/README.md`, `README.md` counts), and one-shot spec-specific migrations. These have no useful purpose in a consumer project — they encode FORGE's own workflow.
- **Runtime** scripts operate on consumer-project artifacts: `AGENTS.md`, command bodies under `.claude/commands/` and `.forge/commands/`, and other files the consumer project owns. These need to ride along in the rendered template so consumers can run them locally.

Without a written policy, future scripts get classified inconsistently — that's the gap Spec 341's AC 4 audit surfaced and Spec 393 closes.

## Classification criteria

A script is `propagate` (mirrored to `template/scripts/`) when **all** of the following hold:

1. It operates on artifacts owned by the consumer project (not FORGE's own internal artifacts).
2. It is invoked by a process-kit gate, hook, or workflow step that ships in the template.
3. It has cross-platform parity (`.sh` + `.ps1`) when invoked from operator-facing surfaces, OR is a self-contained `.py` invoked through a wrapper that handles platform.

A script is `framework-internal` (canonical-only) when **any** of the following hold:

1. It operates on FORGE's own dev artifacts (release tooling, sync tooling, audits over canonical-only files, validators that read FORGE's `docs/specs/`, etc.).
2. It is a one-shot migration tied to a single spec ID (`spec-NNN-*.sh`).
3. It generates content that ships in the template (the script itself is a build-time tool, not a runtime artifact).

The two sets are disjoint and exhaustive over `scripts/*.{sh,ps1}` — every file fits exactly one category.

## Table scope

The Classification Table below covers `scripts/*.sh` and `scripts/*.ps1`. Scripts written in other extensions (currently `.py`, e.g., generators and one-shot migrations) are addressed in [Future extension: `.py`](#future-extension-py) — they are not part of the audited propagation surface yet because the dual-check gate that enforces propagation parity (Spec 188 / Spec 341) is keyed off `.sh`+`.ps1` filenames and PowerShell-parity expectations.

Scripts mirrored to `template/scripts/` but absent from canonical `scripts/` (e.g., `gate-comparison-corpus.sh`) are out of scope for this table — canonical is the authoritative side, and template-only files are tracked separately under their owning spec.

## Classification table

| File | Classification | Rationale |
|------|----------------|-----------|
| backfill-valid-until.sh | framework-internal | Spec 363 one-time backfill of `valid-until:` for FORGE's own draft specs |
| compose-modules.sh | framework-internal | Spec 139 — composes FORGE command files from core + enabled modules at build time |
| cut-release.ps1 | framework-internal | Spec 291 release tooling — drafts forge-public release tags from FORGE audit doc |
| cut-release.sh | framework-internal | Spec 291 release tooling — drafts forge-public release tags from FORGE audit doc |
| gen-command-reference.sh | framework-internal | Generates `docs/command-reference.md` from `template/.claude/commands/*.md` (build-time) |
| run-all-fixtures.sh | framework-internal | Runs FORGE's own `.forge/bin/tests/` fixture suite (FORGE-dev-only) |
| safety-backfill-audit.ps1 | framework-internal | Spec 387 one-time audit over FORGE's pre-existing safety-schema declarations |
| safety-backfill-audit.sh | framework-internal | Spec 387 one-time audit over FORGE's pre-existing safety-schema declarations |
| smoke-test-runtime.sh | framework-internal | Spec 013 cross-platform smoke test exercising a rendered FORGE template |
| smoke-test-template.sh | framework-internal | Spec 199 — verifies the Copier template renders cleanly with `--defaults` |
| spec-344-sync-sentinels.sh | framework-internal | Spec 344 atomic sentinel sync across canonical mirror locations (one-shot) |
| spec-370-sync-matrix-hygiene.sh | framework-internal | Spec 370 atomic sentinel sync into matrix.md mirrors (one-shot) |
| sync-digests.sh | framework-internal | Spec 136 — copies external digest files from NanoClaw into FORGE `docs/digests/` |
| sync-to-public.sh | framework-internal | One-way sync from canonical FORGE repo to forge-public sanitized mirror |
| validate-agents-md-drift.ps1 | propagate | Spec 330 drift detector between AGENTS.md prose and YAML auth-rule block |
| validate-agents-md-drift.sh | propagate | Spec 330 drift detector between AGENTS.md prose and YAML auth-rule block |
| validate-authorization-rules.ps1 | propagate | Spec 327 — lints command bodies against AGENTS.md auth-rule YAML block |
| validate-authorization-rules.sh | propagate | Spec 327 — lints command bodies against AGENTS.md auth-rule YAML block |
| validate-bash.sh | framework-internal | Strips Jinja2 tags + runs shellcheck across FORGE template bash scripts |
| validate-command-integration.sh | framework-internal | Spec 197 — detects island commands inside FORGE's own command surface |
| validate-public-docs.sh | framework-internal | Style-guide check over the forge-public sanitized doc subset |
| validate-readme-counts.sh | framework-internal | Verifies FORGE README.md numeric claims (commands/roles/specs/sessions) |
| validate-readme-stats.sh | framework-internal | Spec 199 — verifies FORGE README.md counts match filesystem reality |
| validate-spec-index.sh | framework-internal | Spec 199 — verifies `docs/specs/README.md` matches FORGE's own filesystem |
| validate-spec-integrity-sentinels.ps1 | framework-internal | Spec 367 CI parity gate over Spec 344 spec-integrity sentinel regions |
| validate-spec-integrity-sentinels.sh | framework-internal | Spec 367 CI parity gate over Spec 344 spec-integrity sentinel regions |
| validate-surface-enumeration.ps1 | framework-internal | Enforces parity between release-policy command list and `.claude/commands/` |
| validate-surface-enumeration.sh | framework-internal | Enforces parity between release-policy command list and `.claude/commands/` |

Counts: 4 `propagate` (the AGENTS.md auth-rule lint surface, both shells), 24 `framework-internal`. Total 28 rows = `ls scripts/*.{sh,ps1} | wc -l`.

## Future extension: `.py`

Two `.py` files in canonical `scripts/` currently relate to the propagation surface:

- `migrate-to-derived-view.py` — mirrored to `template/scripts/` (Spec 399 derived-view migration); behaves as `propagate` in practice.
- `spec-344-insert-guards.py`, `spec-344-insert-sentinels.py` — one-shot migrations for Spec 344; `framework-internal`.

The remaining `.py` files (`build-article-*.py`, `build-smileyforge.py`, `gen_pptx_*.py`) are FORGE-internal content-generation tools and stay canonical-only.

These are documented here for completeness, but `.py` is not yet covered by the dual-check gate and is therefore not in the audited table above. When the propagation surface formally extends to `.py`, the table should grow to include them and the row-count assertion should be amended to count `scripts/*.{sh,ps1,py}` (matching propagation surface).

## Deferred validator enforcement

Spec 393 ships this doc as Phase 1. Automated validator enforcement (a CI gate that fails the build if a script's classification drifts from its actual mirror state) is **deferred** to a follow-up spec.

Re-activation trigger: **first observed propagation drift after this doc ships, OR 90 days post-close (2026-08-01)**, whichever comes first. The deferred-scope item is also captured in `docs/backlog.md` per Spec 393 AC 7.

Until enforcement ships, this policy is operator-enforced at `/implement` review time and at `/close` validator review (a reviewer sanity-checks new entries against the criteria above).

## See also

- [docs/process-kit/runbook.md](runbook.md) — operational runbook (cross-references this policy).
- Spec 270 — Generalized cross-level sync (the propagation pattern this policy documents).
- Spec 341 — AC 4 audit that surfaced the gap.
- Spec 393 — this policy's spec.
