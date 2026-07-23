# FORGE Roadmap

What has shipped, what is in progress, what is in preview, and what is deferred — classified
against actual release data. Every "released" claim cites the release or closed spec that
delivered it; anything without a citation belongs in a later section, not in "released."
(Restructured 2026-07-17, Spec 573 — the previous version of this document presented the
autonomy-escalation phase history with several capabilities marked delivered that are preview
or deferred; this version reconciles the classification with README, FAQ, and VERSIONING.)

Day-to-day prioritization lives in the project backlog and is surfaced by `/now` and `/matrix` —
this document tracks capability-level status only.
The framework currently ships 34 active slash commands — see the generated
[command reference](command-reference.md) for the authoritative, provenance-stamped list.

## Released

| Capability | Release / specs |
|---|---|
| Spec-driven Solve Loop (`/spec` → `/implement` → `/close`) with evidence gates, change lanes, session logging | v1.0.0 (2026-04-11) |
| Evolve Loop with structured signal capture; always-on retro capture at `/close` | v1.0.0; Spec 340 (v3.0.0) |
| Signal-threshold `/evolve` admission (calendar cadence retired; 30-day soft nudge only) | Spec 500 |
| 17 role-separated agents (pipeline roles + DA/MT/Competitor + 11 CxO advisors); `/consensus` multi-role review, Workflow-native fan-out | v2.x; Spec 524 |
| Command chaining / auto-progression (L2) with decision-point pauses | v2.0.0 phase-1 chaining; Spec 498 (chain contract) |
| Deferred-close chaining with the `git push` permission-prompt gate (L1–L2 enforced) | Specs 494–498 |
| **Plugin-primary distribution** — signed Claude Code plugin ships the full framework surface | v3.0.0 (2026-07-16); Specs 463, 487–491; ADR-502 |
| Plugin-native project scaffold — `/forge init` with zero Copier (Copier retained as explicit legacy path) | Spec 557 (in v3.0.0) |
| Structured debugging command (`/debug`, hypothesis-first) | Spec 525 |
| `/reconcile` — ingest work committed outside FORGE into the spec corpus | Spec 486 |
| Generated reference docs with provenance + revision history, drift-gated; audience-scoped link-integrity publish gate | Specs 571, 574 |
| Multi-agent runtime infrastructure — orchestrator, kill switch, worktree isolation, swarm budgets | v2.x (Spec 042 budgets); see Preview for the autonomy levels that exercise it |
| MCP documentation servers (Context7, Fetch) declared per-project | v1.0.0 |

## Current

- **v3 documentation alignment** — plugin-primary rewrite of the consumer journey and conceptual
  docs (Specs 572, 573 — this cycle).
- **Consumer-tier hardening** — the plugin payload is minisign-signed as of v3.0.0; further
  distribution-tier provisioning is in progress.

## Preview

Infrastructure exists and is exercised on FORGE's own development, but the hard guarantee or the
production packaging is not complete:

- **L3 Trusted Autonomy / L4 Full Autonomy** — L3 runs daily on FORGE's own development; the
  L3/L4 push-gate guarantee is *designed, not enforced* until the server-managed settings trust
  root lands (ADR-453 §6.1). Deferred-close chaining is therefore restricted to L1–L2. L4's
  scheduled-trigger envelope is declarative-only (Spec 531 / ADR-531).
- **Async gate review via NanoClaw messaging** (Telegram/WhatsApp/Slack) — optional integration
  for L3+; opt-in, packaged separately.
- **Multi-agent swarms at scale** — parallel spec delivery with conflict detection ships
  (`/parallel`, `/scheduler`); large-swarm operation remains operator-supervised.

## Deferred / roadmap

Not in the current public release — do not build compliance processes on these yet:

- **Lane B Compliance Engine** — pluggable compliance profiles (IEC 61508, EU 2023/1230,
  ISO 13485, IEC 62443), bidirectional traceability, V&V reports, spec sealing. Lane-gate
  scaffolding exists in the command bodies; the engine itself requires additional validation
  before it ships (see FAQ — "Is the compliance engine production-ready?" → No).
- **Hardware Authentication (PAL)** — YubiKey challenge-response for gate decisions; will be
  required for Lane B, optional for Lane A. In development; `gate.provider: prompt` is the
  supported mode today.
- **Server-managed settings trust root** — the agent-immutable enforcement layer that upgrades
  the L3/L4 push-gate from designed to enforced (ADR-453; unlocks chaining above L2).
- **Public-repo CI** — the maintainer CI workflow runs on the private canonical repo; a public
  variant awaits the generated-surface publication model settling (evaluated and deferred at
  Spec 572 — publishing the current workflow would fail on the public tree).
- **Dynamic model routing** — deliberately retired, not pending: frontmatter tier-routing was
  removed because nothing consumed it (Spec 316 / ADR-316); model tiering is operator-advisory
  and the IDE model picker is the real selector.

---

*Classification reconciled with README (§ Roadmap / § Autonomy levels), FAQ, and VERSIONING.md —
Spec 573, 2026-07-17. The historical phase-by-phase delivery narrative (autonomy phases 1–4 and
their spec lists) is preserved in this file's git history.*
