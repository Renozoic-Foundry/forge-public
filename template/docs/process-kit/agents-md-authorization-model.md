<!-- Last updated: 2026-04-29 -->

# AGENTS.md Authorization Model — Operator Guide

This page explains the two-sided model that governs **authorization-required commands** in FORGE, the two linters that keep the sides in sync, and a triage decision tree for resolving drift findings.

You are reading this because:
- A linter emitted `GATE [authorization-rule-lint]: WARN/FAIL` (Spec 327, Step 7c) or `GATE [agents-md-drift]: WARN/FAIL` (Spec 330, Step 7d), and you need to decide what to fix.
- You are editing AGENTS.md prose or the YAML block during onboarding / `/config-change` / `/consensus` follow-up.
- You are onboarding a contributor to the FORGE framework itself.

---

## Overview

FORGE distinguishes **authorization-required commands** — actions whose failure mode is irreversible or carries off-machine blast radius — from ordinary commands. Authorization-required actions need explicit operator invocation (`yes` / a typed command) before any agent runs them. The canonical list lives in `AGENTS.md` § *Authorization-required commands*.

Historical context: three repeated incidents (EA-025, EA-026, EA-027 in `docs/sessions/error-log.md`) had agents running `/close`, `git push`, or destructive git ops across context-compaction boundaries on assumed prior authorization. The fix was a structural one — give the linter something to enforce.

---

## The Two-Sided Model

The authorization rules are documented in **two places** in `AGENTS.md`, deliberately:

| Side | Format | Audience | Purpose |
|------|--------|----------|---------|
| **Prose** | `### Authorization-required commands` bullet list | Operator-readable | Operator skim; explains *why* each action requires authorization |
| **Block** | `<!-- forge:auth-rules:start --> ... <!-- forge:auth-rules:end -->` YAML block | Machine-readable | Linter input for the Spec 327 body lint (Step 7c) |

Both sides authorize the same actions. The two-sided design lets the prose evolve in operator-friendly language (e.g., `force push`) while the block stays in canonical action names (e.g., `git_push_force`). An alias map (`scripts/agents-md-action-aliases.yaml`) bridges phrasing differences. Drift between sides is itself a defect class — Spec 330's drift detector catches it before the body linter reports a silent gap.

---

## The Linters

| Linter | Spec | What it checks | Step |
|--------|------|----------------|------|
| `validate-authorization-rules.sh` | 327 | Each command body that performs an authorization-required action gates that action with a confirmation prompt within the configured proximity window. | 7c |
| `validate-agents-md-drift.sh` | 330 | The action set declared in the YAML block matches the action set enumerated in the prose bullets (modulo the alias map). | 7d |

Both run in **advisory** mode at first ship. Advisory means `WARN` on violations but never blocks `/close`. The flip to `strict` (where `WARN` becomes `FAIL`) is governed by **Spec 332**'s advisory→strict flip plan — see [advisory-to-strict-flip-plan.md](advisory-to-strict-flip-plan.md). Step 7d's mode must flip first; only after prose↔block alignment is clean can Step 7c flip.

---

## The Alias Map

`scripts/agents-md-action-aliases.yaml` (and its template mirror) controls how prose phrasing maps to canonical block action names. Three semantic sections:

| Section | Purpose | Example |
|---------|---------|---------|
| `aliases:` | Normalize a prose phrasing to a canonical block action. | `"force push"` → `git_push_force` so `### force push (--force-with-lease only)` in prose matches the `git_push_force` block entry. |
| `ignore_prose:` | List prose phrasings that intentionally have no block counterpart (e.g., narrative-only mentions). | `"do NOT skip hooks"` — appears in prose explainer but no machine-enforceable action exists. |
| `ignore_block:` | List block actions that intentionally have no prose bullet (e.g., a sub-pattern subsumed by a higher-level prose rule). | `git_reset_hard` — covered in prose under the broader "destructive git operations" bullet. |

**When to add to which section**:
- A real action exists on both sides but the prose uses different words → `aliases:`.
- The prose is talking *about* an action without authorizing it → `ignore_prose:`.
- The block enforces a finer-grained rule than the prose articulates → `ignore_block:`.

**Antipattern (DA finding from Spec 330 round 2)**: do NOT use `ignore_*` as a silent escape hatch when the real fix is to add the missing prose/block entry. Each `ignore_*` row should carry a one-line `comment:` explaining why the asymmetry is intentional. Periodic audit (suggested cadence: every `/evolve` loop) catches stale ignore entries.

---

## Triage Decision Tree

When a linter emits `WARN` or `FAIL`, four observable outputs map to four fixes:

### 1. `prose-only: <action>` (Spec 330 / Step 7d)

The action is mentioned in AGENTS.md prose but absent from the YAML block.

- **Decision**: Should the body linter (Step 7c) enforce this action?
  - **YES** → add the action to the YAML block (canonical name; matches prose semantically).
  - **NO** → add the prose phrasing to `ignore_prose:` with a one-line `comment:` explaining why.

### 2. `block-only: <action>` (Spec 330 / Step 7d)

The action is declared in the YAML block but no prose bullet authorizes it.

- **Decision**: Is the prose missing a bullet?
  - **YES** → add a prose bullet under `### Authorization-required commands` describing the action in operator-readable terms.
  - **NO** (action is intentionally a sub-pattern of an existing prose bullet) → add to `ignore_block:` with a one-line `comment:`.

### 3. `malformed alias-map entry: <field>` (Spec 330 config error)

The alias YAML failed to parse or has empty/invalid targets.

- **Decision**: Open `scripts/agents-md-action-aliases.yaml`, locate the entry, ensure every alias has a non-empty `target:` and every `ignore_*:` entry is a non-empty string. Save. Re-run the drift detector.

### 4. `Step 7c violations: <command-body-paths>` (Spec 327 / Step 7c)

A command body performs an authorization-required action without a confirmation prompt within the proximity window.

- **Decision**: This is body lint, not prose↔block drift. See **Spec 326** ([docs/specs/326-...](../specs/)) for the body-violation triage procedure. Typical fixes:
  - Add a confirmation prompt block ("Push to remote? (yes/no)") before the action.
  - If the action is part of a documentation example (not a real invocation), add a whitelist entry to `scripts/auth-rules-whitelist.yaml` with an explicit `reason:`.

---

## The Strict-Mode Flip

Both linters ship in advisory mode by design — the body lint surfaced 32 first-run violations on Spec 327's first run, all dispositioned in Spec 326. Flipping to strict early would convert those into close blockers across every spec.

The plan ([advisory-to-strict-flip-plan.md](advisory-to-strict-flip-plan.md)) sequences the two flips:
1. **Spec 330 → strict** first. Prose↔block alignment is a precondition for body-lint correctness.
2. **Spec 327 → strict** second, after Spec 326's body-violation triage is fully clean and the change-rate is stable.

Each flip is a one-line edit (`mode: strict` in the AGENTS.md sentinel block) plus a session log entry. Reversion is the same one-line edit back to `advisory`.

---

## FAQ

**Q: I'm adding a new authorization-required command. Where do I edit?**
A: Both sides. Prose first (operator readability), then YAML block (canonical action name), then run `bash scripts/validate-agents-md-drift.sh` locally to confirm sync. The alias map only needs an entry if the prose phrasing differs from the canonical name.

**Q: I see a `WARN` but my edit didn't introduce it. Should I fix it?**
A: Yes — advisory mode means inherited drift accumulates. Use the triage tree above. Most cases are 1-2 line fixes. Treat it like fixing a broken-window: each ignored WARN raises the cost of the eventual strict flip.

**Q: When should I add to `ignore_prose:` or `ignore_block:`?**
A: When the asymmetry is *real and intentional*. Examples: prose says "force push (--force-with-lease only)" — the qualifier doesn't translate to the block; the block authorizes any forced push. Or block has `git_reset_hard` and the prose covers it under "destructive git operations" — finer-grained block, coarser prose. Always add a `comment:` so future audits can verify the rationale.

**Q: How often should I audit the ignore-list?**
A: Every `/evolve` loop is a natural cadence — pattern analysis already reviews signals from the close cycle. If an `ignore_prose:` or `ignore_block:` entry no longer applies (the underlying action was removed or the asymmetry was resolved), the entry should be removed.

---

## Cross-references

- [Spec 327](../specs/327-...) — body lint gate (Step 7c)
- [Spec 330](../specs/330-...) — prose↔YAML drift detector (Step 7d)
- [Spec 332](../specs/332-...) — advisory→strict flip plan
- [Spec 326](../specs/326-...) — body-violation triage outcomes
- [advisory-to-strict-flip-plan.md](advisory-to-strict-flip-plan.md) — the flip-plan companion doc
- [scripts/agents-md-action-aliases.yaml](../../scripts/agents-md-action-aliases.yaml) — the alias map
- AGENTS.md § *Authorization-required commands* — the prose authority
- AGENTS.md `<!-- forge:auth-rules:start -->` block — the machine-readable authority
