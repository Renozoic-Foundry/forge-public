# Settings-writer API (planned, deferred)

> **Status**: planned API — **not yet implemented**. The library this document describes is the subject of [Spec 285](../specs/285-onboarding-configure-shared-writer.md), which is **formally deferred** by 6-role consensus (2026-04-30 round 3, re-confirmed 2026-05-09 round 4). This document captures the design knowledge so future operators evaluating re-activation triggers do not have to re-derive the API shape and the staged-vs-direct-apply architectural split from spec rev logs. Carve-out authored under [Spec 418](../specs/418-settings-writer-api-doc-carve-out.md).
>
> Do **not** implement code from this doc until one of the [Re-activation triggers](#re-activation-triggers) fires.

## Overview

The settings-writer is a planned shared library at `.forge/lib/settings-writer.{sh,ps1}` (canonical) with a Copier mirror at `template/.forge/lib/settings-writer.{sh,ps1}`. Its purpose is to provide idempotent, **direct-apply** functions for mutating the six FORGE settings target files:

- `.forge/onboarding.yaml`
- `.claude/settings.json`
- `CLAUDE.md`
- `AGENTS.md`
- `.copier-answers.yml`
- `.mcp.json`

Direct-apply means: each function call resolves to an immediate write of the resolved value to disk, with no staging, diff, or operator-confirm step. The library is intended for post-onboarding configuration tweaks where the project already has a working configuration baseline — not for first-run setup.

## Architectural Note: staged-writes vs direct-apply

There are **two distinct write paths** for the same six settings files. They are deliberately not unified.

### Path 1: staged-writes — `/onboarding` (Spec 315)

`/onboarding` Step B writes to `.forge/state/onboarding-staging/`, computes an LF-normalized SHA-256 integrity manifest, presents a diff prompt to the operator, and only on confirmation atomically applies the staged files to their final locations with halt-on-failure semantics. This flow has load-bearing safety properties:

- **Decline-leaves-pristine**: if the operator declines the diff, no settings file on disk is touched.
- **Atomic-application**: all six target files are applied as a unit; a partial failure halts the whole apply and leaves the previous state intact.
- **Manifest-tamper-detection**: the integrity manifest catches mid-flow corruption of staged files.

These properties matter at first-run because the operator has no working baseline to fall back to — a botched first-run write can leave the project unbootable.

### Path 2: direct-apply — `/configure` (this library, planned)

`/configure` operates on a project that already has a working configuration. It mutates a single setting (or a small batch) at a time in response to operator intent (e.g., flip a feature flag, change the test command, enroll an agent). The safety constraints differ:

- The operator already has a working baseline — partial failure is recoverable from git or by re-running the command.
- Each operation is small, single-key, and reviewable in a normal commit diff.
- The staging-then-apply ceremony adds friction without proportionate safety value.

So `/configure` writes directly: each `set_*` function modifies its target file in place; `write_all` flushes any buffered changes.

### Why the split is permanent (not a refactor opportunity)

[Spec 285's revision log dated 2026-04-30](../specs/285-onboarding-configure-shared-writer.md) records the consensus decision that this split is the correct end state, **not** an interim state to be unified later. Two unification paths were considered and rejected:

1. **Collapse Spec 315's two-phase flow into the shared library** — rejected because it regresses the `decline-leaves-pristine` safety property on the first-run path.
2. **Parameterize the shared library with `--mode={stage,apply}`** — rejected because the staging logic (manifest computation, diff presentation, atomic apply, halt-on-failure, stale-staging detection) is too thick for a settings-writer primitive. If a future non-`/onboarding` command needs staged settings-writes, the right move is a separate `staged-writes-library` extraction, not parameterization of this primitive.

The two paths share the **target file format** (same six files, same key shape) but not the **write discipline**. The settings-writer library exists for the latter.

## Function Reference (planned)

All functions below are **planned** — not yet implemented. Signatures and semantics may shift before the first concrete second caller materializes (see [Re-activation triggers](#re-activation-triggers)).

### `set_primary_stack <value>`
Sets `project.primary_stack` in `.forge/onboarding.yaml`. Idempotent: calling with the current value is a no-op.

### `set_test_command <value>`
Sets `project.test_command` in `.forge/onboarding.yaml`. Idempotent.

### `set_lint_command <value>`
Sets `project.lint_command` in `.forge/onboarding.yaml`. Idempotent.

### `set_autonomy_level <L0-L4>`
Sets the autonomy level in `AGENTS.md` `forge.autonomy.level`. Validates input against the L0-L4 enum.

### `set_methodology <value>`
Sets `project.methodology` in `.forge/onboarding.yaml` (schema extension; see [Spec 359](#schema-reference)).

### `set_agent <agent_key> <true|false>`
Toggles a CxO agent in `AGENTS.md` `forge.agents.<agent_key>.enabled`. Validates `agent_key` against the registered agent set.

### `set_feature <feature_key> <true|false>`
Toggles a feature flag in `AGENTS.md` `forge.features.<feature_key>` or `.forge/onboarding.yaml` `features.<feature_key>` (path resolved per schema).

### `set_mcp_server <name> <true|false>`
Adds or removes an MCP server from `.mcp.json` and the corresponding `.forge/onboarding.yaml` `mcp_servers.<name>` registry entry.

### `set_project_identity <name> <description>`
Sets `project.name` and `project.description` in both `.forge/onboarding.yaml` and `.copier-answers.yml`. The two files share the identity surface — both must update atomically.

### `write_all`
Flushes any buffered changes to disk. Direct-apply implementations may make this a no-op (each `set_*` writes immediately); buffered implementations use it to commit a batch.

## Primitive choice

[ADR-359](../decisions/) records the decision to use **Python + stdlib** (no third-party dependency on PyYAML, `jq`, or `yq`) as the file-edit primitive for the settings-writer library. Rationale (per ADR-359):

- **JSON**: Python stdlib `json` handles `.claude/settings.json`, `.copier-answers.yml` (YAML-compatible JSON-shape), and `.mcp.json` natively without dependencies.
- **YAML**: Python stdlib has no YAML parser, but the FORGE schema (`.forge/onboarding.yaml`, see [Spec 359](#schema-reference)) is constrained to top-level scalars and one-level-deep mappings. Line-regex round-trip works for this constrained shape; full PyYAML is unnecessary.
- **Markdown frontmatter** (`CLAUDE.md`, `AGENTS.md`): YAML frontmatter or sentinel-delimited blocks; treated the same way as the YAML files above.
- **Cross-platform**: PowerShell parity uses the same approach (`ConvertFrom-Json`, line-regex for YAML).

This rules out the alternative of building shell-only YAML editors in pure bash, which the original Spec 285 inline-write logic attempted and which Spec 285's 2026-04-28 implementation pause flagged as non-trivial.

## Schema reference

[Spec 359](../specs/359-onboarding-schema-reconciliation.md) (closed 2026-04-28) reconciled the `.forge/onboarding.yaml` schema. Key points relevant to this library:

- **Top-level keys**: `status`, `phases`, `features`, `mcp_servers`, `setup_tasks`, `project`.
- **`project` sub-keys**: `name`, `description`, `primary_stack`, `test_command`, `lint_command`, `methodology` (added in Spec 359).
- **Agent registry**: lives in `AGENTS.md` `forge.agents.*`, not `.forge/onboarding.yaml`. The `set_agent` function targets `AGENTS.md`.

This schema is the contract the library writes against. Schema changes are out of scope for the library; they belong in their own spec with a migration story.

## Re-activation triggers

[Spec 285's 2026-04-30 defer](../specs/285-onboarding-configure-shared-writer.md) declared two re-activation triggers. Either one fires → re-score Spec 285 against then-current state, then `/implement`:

- **Trigger (a)** — A **second concrete direct-apply caller** is specced. Examples cited in the defer entry: `/re-onboard --reset-key`, `/configure-batch`, a CI hook that needs to mutate the same 6 settings files. The trigger fires when such a spec exists in `docs/specs/` (status `draft` or further) — not when it's merely contemplated.
- **Trigger (b)** — A /configure drift bug recurs that a shared writer would have prevented. "Drift" here means inconsistent behavior across the 4 `/configure` mirrors due to inline-write logic divergence; the trigger fires when such a bug is filed as a signal in `docs/sessions/signals.md` or as a hotfix-lane spec.

Re-confirmation on 2026-05-09 (round 4): neither trigger had fired in the 9 days since defer (zero `/configure` commits, no second-caller spec, no drift signal). The defer holds.

The `/implement` halt that fires when an operator runs `/implement 285` while neither trigger has fired is the enforcement mechanism for this gate. Lifting the defer requires citing which trigger fired in the operator-facing prompt and recording the trigger's evidence in the Spec 285 revision log at the start of the new `/implement` cycle.

## Usage Pattern (planned)

When the library is eventually shipped, callers should follow this pattern:

```sh
# Bash example
source .forge/lib/settings-writer.sh
set_primary_stack "python"
set_test_command "pytest -q"
set_feature "review.enabled" true
write_all  # flush any buffered changes (no-op for direct-apply impls)
```

```powershell
# PowerShell parity
. .forge/lib/settings-writer.ps1
Set-PrimaryStack "python"
Set-TestCommand "pytest -q"
Set-Feature "review.enabled" $true
Write-All
```

### When to call this library

- Post-onboarding configuration tweaks where a working baseline already exists.
- Single-key or small-batch mutations where commit-diff review is sufficient safety.

### When NOT to call this library

- **First-run onboarding** — use `/onboarding` Step B's staged-writes flow ([Spec 315](../specs/315-onboarding-staged-writes-and-mature-repo-detection.md)). The staging-then-apply ceremony exists for first-run safety; bypassing it via this library defeats `decline-leaves-pristine` and atomic-application.
- **Bulk schema migrations** — multi-key edits where consistency across files matters more than atomicity per call. Build a migration script that uses this library's primitives; the library itself is not the orchestrator.
- **Settings files outside the canonical six** — extend the schema (per [Spec 359](#schema-reference)) and add a typed function rather than calling a generic file-edit helper.
