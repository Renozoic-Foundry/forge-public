# Scheduled strategy-only routines

<!-- Last verified: 2026-06-15 against Spec 459 -->

Spec: [459](../specs/459-scheduled-strategy-routines.md). Extends Spec
[458](../specs/458-signal-to-strategy-loop-prd.md) (Signal-to-Strategy Loop —
supplies the loop-contract shape reused here). Under the Spec 449 (Claude Code 2026
Alignment) umbrella.

This guide defines three **scheduled, artifact-producing, lifecycle-neutral**
routines that let discovery and review compound without manual re-invocation. Each
routine is a "green" routine: it produces reviewable artifacts in the triage inbox
and **never advances the spec lifecycle or expands autonomy**.

> **Green-routine invariant (Spec 459 Constraints).** These routines MUST NOT
> dispatch `/implement` or `/close`, MUST NOT `git commit`, and MUST NOT write any
> autonomy or budget config. The autonomous implement/close routine is explicitly
> **deferred to PRD-001 ("Evidence-Debt Engine") Phase 1** and is out of scope here.
> The boundary is enforced by each contract's forbidden-actions list plus the
> existing edit-gate / commit-guard hooks and operator discipline (runtime
> enforcement is PRD-001 / NC-2 territory — see Spec 459 Verification Scope (c)).

---

## The three green routines

| Routine | Command | Reads | Emits to triage | Cadence (default) |
|---------|---------|-------|-----------------|-------------------|
| `consensus-vet-pending` | `/consensus` (vet) | draft specs + registry roles | per-draft vet summary | weekly |
| `evolve-scan` | `/evolve` (scan only) | signals, watchlist, guide freshness | process/watchlist scan summary | biweekly |
| `brainstorm-digests` | `/brainstorm` | unreviewed digests + fired watchlist triggers | spec-candidate entries | weekly |

Each routine has a one-page loop contract at
`.forge/loops/<name>.contract.yml`. The contracts **reuse Spec 458's loop-contract
shape** (`docs/process-kit/signal-to-strategy-loop.md` §1) — name, purpose, trigger /
cadence, read-only input scope, allowed actions, **forbidden actions**, outputs, stop
conditions, escalation boundary, verification. There is no parallel/duplicate format.

---

## Loop contracts (one page each)

### 1. consensus-vet-pending

Contract: [`.forge/loops/consensus-vet-pending.contract.yml`](../../.forge/loops/consensus-vet-pending.contract.yml)

| Field | Value |
|-------|-------|
| **Trigger / cadence** | Scheduled, weekly (operator-tunable). |
| **Scope (read-only)** | `docs/specs/*.md` (drafts only), `docs/specs/README.md`, `.claude/agents/*.md`. |
| **Outputs** | Triage inbox only: `docs/sessions/triage/consensus-vet-<date>-spec-<NNN>.md`. |
| **Forbidden** | `/implement`, `/close`, `git commit`, autonomy config write, budget config write, spec lifecycle advance. |
| **Stop** | All pending drafts vetted; or no pending drafts; or operator pause. |

### 2. evolve-scan

Contract: [`.forge/loops/evolve-scan.contract.yml`](../../.forge/loops/evolve-scan.contract.yml)

| Field | Value |
|-------|-------|
| **Trigger / cadence** | Scheduled, biweekly (operator-tunable). |
| **Scope (read-only)** | `docs/sessions/signals.md`, `docs/sessions/watchlist.md`, `docs/process-kit/*.md` (freshness), `docs/sessions/*.json` (acceptance rate). |
| **Outputs** | Triage inbox only: `docs/sessions/triage/evolve-scan-<date>.md`. |
| **Forbidden** | `/implement`, `/close`, `git commit`, autonomy config write, budget config write, the full `/evolve` loop, spec lifecycle advance. |
| **Stop** | Scan summary written; or nothing flagged; or operator pause. **Scan only** — never runs the full `/evolve` loop. |

### 3. brainstorm-digests

Contract: [`.forge/loops/brainstorm-digests.contract.yml`](../../.forge/loops/brainstorm-digests.contract.yml)

| Field | Value |
|-------|-------|
| **Trigger / cadence** | Scheduled, weekly (operator-tunable). |
| **Scope (read-only)** | `docs/digests/` (unreviewed), `docs/digests/reviewed.md`, `docs/sessions/watchlist.md`, `docs/backlog.md`, `docs/specs/README.md`. |
| **Outputs** | Triage inbox `docs/sessions/triage/brainstorm-digests-<date>.md`; may append review markers to `docs/digests/reviewed.md` and a watchlist candidate (additive existing-artifact destinations only). |
| **Forbidden** | `/implement`, `/close`, `git commit`, autonomy config write, budget config write, **create draft spec file**, spec lifecycle advance. |
| **Stop** | All unreviewed digests reviewed and candidates logged; or none remain; or operator pause. Emits spec **candidates**, never creates a spec. |

---

## Triage-inbox disposition flow

Routine outputs land in [`docs/sessions/triage/`](../sessions/triage/) (see its
[README](../sessions/triage/README.md) for entry naming and shape). The flow:

1. A scheduled routine writes a triage entry (plus, where its contract allows,
   appends review markers to existing artifacts such as `reviewed.md`).
2. `/now` surfaces the triage-inbox count.
3. The **operator** reviews each entry and decides a disposition
   (`ready-for-review`, `needs-revision`, `graduate-to-spec`, `defer/watch`,
   `discard`).
4. The operator — never the routine — runs any lifecycle command (`/spec`,
   `/implement`, `/close`) that a disposition implies.
5. The operator clears dispositioned entries from the inbox.

The triage inbox is the **hard boundary** between automated discovery/review and
operator-authorized action. Routine outputs are written only to the triage inbox
plus the existing artifact destinations named in each contract — never to a
lifecycle-advancing state.

---

## On-box (default) vs remote (InfoSec-approval-gated)

Routines reuse **native** scheduling primitives only — no custom scheduler, daemon,
or background service (ADR-359, native-over-custom). Two execution modes:

| Mode | Mechanism | Default? | Rationale |
|------|-----------|----------|-----------|
| **`on-box`** | Native `CronCreate` (host cron) or in-session `/loop <interval> <command>` | **Yes (hard default)** | Specs, code, and signals stay **inside the org boundary**. No project content leaves the operator's machine. No external-system trust required. |
| **`remote`** | Remote routines / `/schedule` (cloud-executed cron agents) | **No — InfoSec-approval-gated** | A remote routine ships repo context to a cloud execution surface. This crosses the org boundary, so it requires explicit **InfoSec approval** and explicit operator opt-in before it may be reached. |

**`on-box` is the hard default.** The `remote` `execution_mode` MUST NOT be reachable
without explicit operator opt-in (Spec 459 Constraints). The rationale is the
org-boundary one above: specs/code are sensitive, so the default keeps them on the
operator's machine; remote execution is a deliberate, approval-gated exception.

Wiring a routine to actually fire on a real cadence is **operator configuration**
(host cron entry or a running `/loop`), not template code — the template ships the
contracts and this guide; the operator schedules them.

---

## `forge.routines` config

The routine defaults live in `AGENTS.md` under `forge.routines`:

```yaml
forge.routines:                  # Spec 459 — scheduled strategy-only (green) routines
  enabled: false                 # OFF by default — operator opts in
  cadence: weekly                # default cadence; per-routine override in each contract
  pausable: true                 # routines can be paused without losing state
  execution_mode: on-box         # on-box (default) | remote (InfoSec-approval-gated)
```

`enabled: false` is the default — routines do nothing until the operator opts in.

---

## What these routines never do

- They never dispatch `/implement` or `/close`.
- They never `git commit` or `git push`.
- They never write autonomy level, `auto_progression`, budget ceilings, or swarm budget.
- They never advance a spec's `Status` field or create a draft spec file.

These are enumerated as **forbidden actions** in every contract (grep-verifiable) and
are the structural guarantee that the routines stay lifecycle-neutral.
