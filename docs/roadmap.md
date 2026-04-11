# FORGE Autonomy Escalation Roadmap

This roadmap defines the phased progression from FORGE's current human-driven workflow to fully autonomous agentic development with messaging-based human-in-the-loop review.

Each phase builds on the previous. No phase can be skipped — the evidence gates and infrastructure from earlier phases are prerequisites for later ones.

---

## Current State

**All four autonomy phases are delivered as template infrastructure.** FORGE operates at **L2 autonomy** in daily use (supervised, command chaining) with all infrastructure for L3–L4 in place. 120 specs closed, 7 draft, 11 deprecated across 23 sessions (2026-03-13 through 2026-03-28). 139 total spec entries.

**What works today:**
- Spec-driven development with evidence gates (27 active slash commands + 6 deprecated)
- Agent role separation with context-scoped isolation (Spec 099) — DA and validator as isolated subagents
- OCI container isolation for permission enforcement
- Budget tracking (time-based) with dynamic model routing (Spec 085)
- Kill switch procedure with YubiKey hardware authentication
- CI pipeline for template validation
- Command chaining with structured gate outcomes (Specs 019, 020)
- Auto-progression configuration per autonomy level in AGENTS.md (Spec 021)
- `set -e` safe bash patterns across all template scripts (Spec 022)
- `/brainstorm` command for roadmap-driven spec discovery (Spec 018)
- **NanoClaw IPC gate bridge** — async review via Telegram/WhatsApp/Slack (Specs 053, 054)
- **YubiKey HMAC-SHA1 mutual authentication** for gate decisions (Specs 033, 050)
- **Persistent gate state** — file-per-spec JSON with full audit trail (Spec 034)
- **Evidence capture tooling** — structured evidence sections in specs (Spec 031)
- **Multi-agent scheduler** and conflict detection (Specs 040, 041) — template infrastructure
- **Automated evolve loop** with signal pattern analysis and spec proposal generation (Specs 043, 044, 045)
- **Lane B compliance engine** — profiles, traceability, gates, V&V reports, spec sealing (Specs 035–039, 052)
- **MCP documentation servers** — Context7, Ansvar EU Regulations, Grounded Docs, Fetch (Spec 027)
- **Copier migration** — template engine with `.jinja` suffix approach (Spec 029)
- **Prompt caching** and **model tiering** with cost tracking (Specs 055, 056, 085)
- **Structured logging** for all bash scripts (Spec 047)
- **Project-scoped insights engine** (Spec 049)
- **Context engineering** for slash commands — context snapshot, parallel reads (Spec 091)
- **Browser test automation** with visual evidence capture (Spec 093)
- **Two-stage subagent review** protocol (Spec 083)
- **Role-based agent pipeline** for spec lifecycle (Spec 078)
- **Skill auto-testing framework** (Spec 079)
- **Spec integrity SHA signatures** (Spec 089)
- **Automated score verification** in spec lifecycle (Spec 088)
- **Backlog dependency tracking** and parallel batch detection (Spec 087)
- **`/forge stoke`** — Copier-based upgrade with AI conflict resolution and missing file restoration (Specs 065, 067, 068, 069)
- **`/forge init`** — unified onboarding path with legacy upgrade (Spec 072; renamed from `/forge light` in Spec 165)
- **Deferred first-session onboarding** (Spec 073)
- **`/interview`** — Socratic elicitation command (Spec 075)
- **Multi-agent command portability** (Spec 076)
- **User-level vs project-level settings split** (Spec 077)
- **Hook-enforced tool restrictions** for role isolation (Spec 100)
- **Worktree path resolution guard** (Spec 101)
- **Knowledge synthesis** (`/synthesize`) — postmortem, topic, decisions, architecture modes (Spec 106)
- **Cross-artifact relationship index** (Spec 108)
- **Command deduplication** — `.claude/` vs `.forge/` consolidation (Spec 111)
- **`/forge` split + lazy-load** — system prompt optimization (Specs 112, 113)
- **DRY pass** — scoring formula + light spec variant (Spec 114)
- **Shadow validation** as first-class pattern (Spec 115, 129)
- **Context anchoring** documentation and guide (Specs 116, 124)
- **Spec Kit MCP integration** (Spec 118)
- **Session handoff schema** (Spec 119)
- **Bash script portability guard** (Spec 121)
- **Context overflow resilience** (Spec 123)
- **Long-running task patterns** guide (Spec 125)
- **Supply chain security gate** (`/dependency-audit`) (Spec 126)
- **ADR template and `/decision` command** (Spec 127)
- **Cognitive debt guardrail** (Spec 128)
- **CLI-first agent compatibility** (Spec 130)
- **UX consolidation** — `/now` hub, 6 deprecations, `/forge` restructure (Spec 131)
- **Documentation cleanup, sync guard, quick reference** (Spec 132)
- **Session identity and spec owner resolution** (Spec 133)
- **Digest ingestion pipeline** for research integration (Spec 136)

**What's next (7 draft specs):**
- Spec 134 — Multi-Agent Concurrent Session Model (score 33)
- Spec 135 — Review Engagement Canary (score 30)
- Spec 090 — Shared Team Baselines (score 28)
- Spec 103 — Git-Signed Audit Trail for Lane B (score 26)
- Spec 109 — Cross-Project Knowledge Bridge (score 26)
- Spec 120 — DX Metrics Dashboard (score 25)
- Spec 122 — Multi-Vendor Model Strategy (score 23)

---

## Phase 1 — Command Chaining and Auto-Progression ✅ COMPLETE
**Autonomy Level: L1+ → L2** | Completed: 2026-03-13

### What was delivered
Commands declare success criteria and auto-chain to the next logical command. When a command succeeds, FORGE proceeds to the next action without waiting for human input. The human remains at the terminal but intervenes less.

### Delivered specs
- **Spec 019** — Command Chaining Mechanism: `/implement` → `/close NNN` and `/close` → `/implement next` chain declarations
- **Spec 020** — Gate Pass/Fail Auto-Detection: Structured `GATE [name]: PASS/FAIL/CONDITIONAL_PASS — reason` outcomes at each checkpoint
- **Spec 021** — Auto-Progression Configuration: Chain permission matrix in AGENTS.md (L0–L4), `pause_at_gates` per level
- **Spec 022** — Bash `set -e` Safety Patterns: 12 unsafe patterns fixed, 4-row safety reference table in CLAUDE.md

### Evidence
- Command chaining validated: `/implement 021` auto-chained to `/close 021` (first live chain), then again for Spec 022
- Gate outcome format operational: all gates emit structured PASS/FAIL with remediation guidance
- L1 default preserves current behavior (no auto-chaining); L2 enables supervised chains
- All 13 bash scripts pass shellcheck; 21 smoke test checks pass

### Key signals from Phase 1
- Chain mechanism is instruction-level (conversation context), not persistent state — works for synchronous single-agent but will need persistent gate state for Phase 2 async/NanoClaw
- Layered architecture validated: gates (signal) → chains (mechanism) → config (policy). Replicate this pattern for Phase 2
- `set -e` footguns are a recurring bash concern — safety patterns doc prevents future incidents

---

## Cross-Cutting Concerns — Infrastructure for All Phases ✅ ALL DELIVERED

These capabilities are not tied to a single phase. They enhance the foundation. All have been delivered as of 2026-03-15.

### Spec Kit Integration
GitHub Spec Kit (github/spec-kit) was part of FORGE's original design. Its specify → plan → tasks pipeline replaces manual spec authoring with structured, agent-guided spec creation. FORGE wraps Spec Kit's output with lifecycle management, evidence gates, and learning capture that Spec Kit does not provide.

**Integration seam:** Spec Kit's `/speckit.specify` → `/speckit.plan` → `/speckit.tasks` feeds into FORGE's `/implement` → `/close` → `/retro` cycle. Spec Kit handles the front half (what to build), FORGE handles the back half (building it with evidence).

### MCP Documentation Servers
Agents working from stale training data is a silent failure mode — especially dangerous for safety-critical work. MCP servers provide live, authoritative documentation:

- **Context7** — Versioned library docs matched to project dependencies (Lane A + B)
- **Fetch** (Anthropic official) — Any URL to markdown on demand (Lane A + B)
- **Ansvar EU Regulations MCP** — 49 EU regulations with daily EUR-Lex sync, raw text only (Lane B)
- **Grounded Docs MCP** — Self-hosted indexing of purchased IEC/ISO PDFs (Lane B)

The `.mcp.json` in the cookiecutter template declares servers per lane. Lane B CLAUDE.md enforces a regulatory accuracy rule: agents must query MCP for current standard text and cite specific articles.

### Single Source of Truth for Spec Status
Spec status currently lives in 4 files (spec file, README, backlog, CHANGELOG). Every transition must update all 4 in lockstep — a consistency burden and source of silent desync. A custom MCP server exposing spec lifecycle as a queryable tool would eliminate this. The MCP server becomes the authoritative source; the 4 files become read views.

### /sync Command and Copier Migration
FORGE's original design included a `/sync` command for bidirectional upstream/downstream updates. Cookiecutter (via Cruft) supports downstream pulls but not upstream pushes. Copier (copier.readthedocs.io) natively supports `copier update` with conflict resolution. `/sync` would orchestrate: Copier update pull + conflict resolution + evidence gate workflow + upstream improvement push.

### Dual-Lane Architecture (Lane A / Lane B)
A `compliance_profile` cookiecutter variable controls Lane B features. When set (e.g., `eu-machinery`, `iso-26262`, `internal`), the template bootstraps the compliance engine: extended spec templates, traceability commands, configurable compliance gates, regulatory MCP servers, and compliance artifact generators. When empty (default), the lean Lane A experience is unchanged.

### Lane B — Compliance Engine (Regulation-Agnostic)
Lane B is not hardcoded to any single regulatory framework. It provides the **engine** — traceability, gates, audit artifacts — and specific regulations are plugged in as **compliance profiles**. Each profile defines:

- **MCP documentation servers** — authoritative sources for the regulation's current text
- **Gate rules** — what static analysis, review, or verification checks are required at each lifecycle transition
- **Artifact templates** — what documentation the compliance framework expects (traceability matrices, V&V reports, safety cases, etc.)
- **CLAUDE.md enforcement rules** — instructions that force the agent to query authoritative sources and cite specific clauses

This means FORGE can enforce compliance with IEC 61508, EU 2023/1230, ISO 26262, FDA 21 CFR Part 11, SOC 2, HIPAA, internal corporate standards, or any framework where authoritative documentation is accessible — either via MCP servers (for public/licensed standards) or self-hosted indexing (for proprietary policies).

The key constraint is **access to authoritative, current documentation**. If the agent can query the regulation text via MCP, FORGE can enforce it. If the documentation is stale or unavailable, the compliance guarantee is hollow.

**Compliance engine capabilities** (each a future spec):
- **Compliance profile schema** — Declarative format defining MCP servers, gate rules, artifact templates, and CLAUDE.md rules per framework
- **Bidirectional traceability matrix** — Req → Design → Code → Test → Evidence, auditable in both directions
- **Lifecycle model mapping** — Spec sections map to the profile's lifecycle model (V-model, Agile, spiral, etc.) with corresponding verification pairs
- **Configurable compliance gates** — Static analysis, review, or verification results as evidence gate artifacts in `/close`, defined per profile
- **Change impact analysis** — `/revise` assesses impact against the profile's risk categories (safety functions, data privacy, security posture, etc.)
- **V&V report auto-generation** — `/close` generates verification/validation reports from captured evidence, formatted per profile requirements
- **Compliance case management** — Living compliance document (safety case, security case, quality case) updated by `/close` and `/revise`
- **Binary/artifact traceability** — CI metadata linking deployed artifacts to exact source commit + toolchain + config
- **Framework practice mapping** — Map FORGE activities to the compliance framework's required practices for auditors
- **Post-release lifecycle** — Tracking for deployed products requiring ongoing compliance (security patches, re-certification triggers, audit readiness)

### Example Compliance Profiles

| Profile | Framework | MCP Sources | Key Gates | Artifact Types |
|---------|-----------|-------------|-----------|----------------|
| `eu-machinery` | EU 2023/1230 + IEC 61508 + IEC 62443 | Ansvar EU Regulations (daily EUR-Lex sync) + Grounded Docs (purchased IEC PDFs) | MISRA C, cybersecurity risk assessment, third-party assessment for AI | Technical file, safety case, V&V reports, traceability matrix |
| `automotive` | ISO 26262 + ASPICE | Grounded Docs (ISO PDFs) | MISRA C/C++, ASIL-rated review, tool qualification | Safety case, DFA/FMEA, HARA |
| `medical` | FDA 21 CFR Part 11 + IEC 62304 | Grounded Docs (FDA guidance PDFs) + Fetch (FDA.gov) | Design controls, DHF completeness, cybersecurity | Design History File, risk management file |
| `fintech` | SOC 2 + PCI DSS | Grounded Docs (AICPA criteria) | Access controls, encryption, audit logging | Trust Services Report, evidence packages |
| `internal` | Corporate engineering standards | Grounded Docs (company wiki/PDFs) | Custom code review, architecture review | Internal compliance report |

The `eu-machinery` profile serves as the reference implementation and north star for Lane B development, driven by the **January 20, 2027** hard deadline for EU Machinery Regulation 2023/1230.

### Compliance Profile Verification Gate
When a compliance profile is activated, FORGE requires a **human sign-off** confirming:
- The MCP documentation sources serve the correct version of each standard/regulation
- The material is complete (no missing sections, amendments, or delegated acts)
- The profile scope is appropriate for the product/project
- The verification has a review date (default: quarterly)

This sign-off is stored as a versioned artifact in the project (`docs/compliance/profile-verification.md`). The agent checks for a valid, non-expired verification before generating compliance artifacts. If the verification is missing or expired, the agent halts and requests human review.

### Liability Disclaimer — Required at Every Layer
FORGE is a process framework, not a certification authority. Every compliance artifact generated by FORGE must carry a disclaimer stating:
- Generated artifacts are aids for qualified professionals, not substitutes for independent verification
- No warranty of compliance is expressed or implied
- The developer and their organization bear full responsibility for regulatory compliance
- Ingested regulatory material must be verified by a qualified human against authoritative sources

This disclaimer must appear in: the README, the compliance profile verification artifact, every generated compliance document (traceability matrix, V&V report, compliance case), and the `/close` output for compliance-profiled projects.

---

## Phase 2 — Async Review via NanoClaw ✅ DELIVERED
**Autonomy Level: L2 → L3** | Infrastructure delivered: 2026-03-14 / 2026-03-15

### What was delivered
FORGE agents no longer require the human at the terminal. Agents run autonomously and contact the human via messaging (WhatsApp, Telegram, Signal, Slack, Discord) through [NanoClaw](https://nanoclaw.dev/) when they reach a gate decision, encounter an error, or need human judgment.

NanoClaw is a lightweight, open-source personal AI agent built on the Claude Agent SDK. Its container isolation, per-group memory, and agent swarms map directly to FORGE's existing architecture:

| FORGE concept | NanoClaw equivalent |
|---------------|---------------------|
| OCI container isolation | Per-group container sandboxing |
| Per-spec session isolation | Per-group memory (isolated CLAUDE.md) |
| Agent role separation | Agent swarms with specialized roles |
| Slash commands | NanoClaw skills |
| Budget enforcement | Concurrency control (GroupQueue) |

### Human experience
- Human starts a FORGE session and walks away
- Agents implement specs, run tests, capture evidence
- When a gate decision is needed, human receives a message on their phone:
  ```
  🔨 FORGE — Spec 023 implemented
  ✅ All 12 tests pass
  📸 [Screenshot: test output]
  📎 [Diff: 3 files changed, +47 -12]

  Gate decision needed:
  → Reply "approve" to close and continue
  → Reply "reject: <reason>" to halt
  → Reply "show me <file>" for details
  ```
- Human approves or rejects from their phone while doing other work
- Rejected gates include the reason, which FORGE uses to retry or escalate

### Delivered specs
- **Spec 033** — Gate Decision Protocol with YubiKey MFA: HMAC-SHA1 mutual authentication, JSON schemas, security library
- **Spec 034** — Persistent Gate State: file-per-spec JSON, append-only audit trail, `forge_gate_state_check_all_pass()`
- **Spec 030** — NanoClaw Adapter: FORGE-to-NanoClaw bridge, gate flow orchestration, skill manifest
- **Spec 031** — Evidence Capture Tooling: structured evidence sections in specs
- **Spec 032** — Session Persistence / Detached Mode: session auto-numbering
- **Spec 050** — Hardware Key Safety, Model Detection & Auth Abstraction: provider abstraction (YubiKey, FIDO2, mobile), safety pre-flight, non-interactive CLI
- **Spec 053** — NanoClaw Container Deployment: docker-compose, `/nanoclaw` slash command
- **Spec 054** — NanoClaw IPC Gate Bridge: file-based IPC transport, natural language gate responses, gate-meta sidecar correlation

### Evidence
- End-to-end gate bridge validated: approve + reject flows confirmed on Telegram (Spec 054)
- YubiKey HMAC-SHA1 challenge-response operational with dual-key enrollment
- IPC transport chosen over HTTP for simplicity and reliability (no port conflicts, atomic writes)

### Key signals from Phase 2
- Non-interactive CLI-first design is mandatory for AI agent contexts (CI-010, SIG-050-I1)
- PATH resilience across Windows/Linux/Mac requires explicit tool path injection (CI-011)
- `ykman otp info` is unreliable for slot status — always verify with actual challenge-response (EA-008)

---

## Phase 3 — Multi-Agent Swarms ✅ DELIVERED (template infrastructure)
**Autonomy Level: L3 → L3+** | Specs delivered: 2026-03-15

### What was delivered
Template infrastructure for multi-agent coordination. Multiple FORGE agents can work in parallel on different specs, coordinated by an orchestrator agent. NanoClaw's agent swarm capability manages the fleet. The human receives consolidated status updates rather than per-agent messages.

### Human experience
- Human sets a goal: "Implement the top 5 backlog specs"
- FORGE orchestrator assigns specs to agents, respecting dependencies
- Human receives periodic digest messages:
  ```
  📊 FORGE Swarm Status — 14:30

  Spec 023: ✅ closed (agent-A)
  Spec 024: 🔨 implementing (agent-B, 67% budget used)
  Spec 025: ⏳ blocked on 024 (agent-C, waiting)
  Spec 026: 🔍 devil's advocate review (agent-D)
  Spec 027: ❌ gate failed — needs human input

  → Reply "details 027" for full context
  → Reply "pause all" to halt swarm
  → Reply "continue" to acknowledge
  ```
- Human intervenes only on failures and gate rejections

### Delivered specs
- **Spec 040** — Multi-Agent Scheduler: dependency-aware scheduling, `/scheduler` command
- **Spec 041** — Cross-Agent Conflict Detection: file-level locking, worktree isolation
- **Spec 042** — Swarm Budget Management: per-agent and aggregate budget caps

### Status
Template infrastructure is in place. The scheduler, conflict detection, and budget management commands exist in the template. Full operational validation requires running multi-agent workloads in a consumer project — this will happen as trust in the system grows.

### Risks (still applicable)
- **High**: Multiple agents operating concurrently increases blast radius
- Merge conflicts between parallel agents — mitigated by conflict detection (Spec 041) and worktree isolation (Spec 003)
- Budget multiplication — 5 agents × budget ceiling = 5× cost potential — mitigated by swarm budget caps (Spec 042)
- Orchestrator failure could leave orphan agents — need heartbeat + cleanup

---

## Phase 4 — Self-Improving Autonomy ✅ DELIVERED (template infrastructure)
**Autonomy Level: L4** | Specs delivered: 2026-03-15

### What was delivered
Template infrastructure for self-improving autonomy. FORGE agents can propose process improvements, create specs for identified gaps, and adjust their own autonomy configuration (subject to human approval of the config change). The evolve loop (KCS Evolve Loop) runs automatically, with signal pattern analysis generating spec proposals.

### Human experience
- FORGE operates continuously, pulling from the backlog
- When the backlog is empty, agents run `/evolve` automatically, analyze signals, and propose new specs
- Human receives weekly digest:
  ```
  📋 FORGE Weekly — March 20, 2026

  Completed: 12 specs closed
  Proposed: 3 new specs from signal analysis
  Process: 2 command improvements suggested
  Budget: $14.20 total spend (under $50 ceiling)

  New spec proposals (need your approval):
  1. Spec 045 — Retry logic for flaky CI jobs
     Signal: SIG-089, SIG-091 (2 failures, same root cause)
  2. Spec 046 — Cache shellcheck results
     Signal: SIG-090 (validation takes 45s, could be 5s)
  3. Spec 047 — Add structured logging to adapters
     Signal: SIG-087 (debugging adapter issues is manual)

  → Reply "approve 1,2" to create specs
  → Reply "drop 3: not worth the complexity" to dismiss
  → Reply "details 1" for full signal context
  ```
- Human provides strategic direction; agents handle execution

### Delivered specs
- **Spec 043** — Automated Evolve Loop Runner: configurable triggers (time, spec count, manual), NanoClaw delivery, human approval gate
- **Spec 044** — Signal Pattern Analysis Engine: type parsing, keyword clustering, severity scoring (impact × frequency), pattern table reporting
- **Spec 045** — Spec Proposal Generation: draft proposals from systemic patterns, approve/modify/dismiss flow, dismissal suppression
- **Spec 046** — Autonomy Config Change Protocol: agent proposes AGENTS.md changes, human approves via message, automatic rollback on rejection

### Evidence
- Signal pattern analysis operational: 2 systemic patterns detected → 2 specs auto-proposed and approved (058, 059) during session 003
- Evolve loop run 4 completed: 3 additional specs proposed from patterns and scratchpad (060, 061, 062)
- The process literally improved itself: signal capture from Spec 047/050 → pattern detection → Spec 058 auto-proposed

### Status
Template infrastructure is in place. Full L4 autonomy (continuous autonomous operation with human approval via messaging) requires operational trust built through L3 usage. The infrastructure is ready; the trust model gates progression.

### Risks (still applicable)
- **High**: Self-modification of autonomy config is the highest-risk capability — mitigated by human approval gate (Spec 046)
- Feedback loops: agents generating specs that generate more agents — mitigated by `max_proposals_per_cycle` config and human approval
- Cost runaway without human attention — need hard budget ceilings with automatic halt
- Specification quality of auto-generated specs may be low — mitigated by devil's advocate gate on all specs

---

## Dependency Graph

```
Phase 1: Command Chaining (L1+ → L2) ✅ COMPLETE (2026-03-13)
├── ✅ Spec 019 — Command chaining mechanism
├── ✅ Spec 020 — Gate pass/fail auto-detection
├── ✅ Spec 021 — Auto-progression config in AGENTS.md
└── ✅ Spec 022 — Bash set -e safety patterns

Cross-Cutting ✅ ALL DELIVERED
├── ✅ Spec 026 — Spec Kit integration
├── ✅ Spec 027 — MCP documentation servers (.mcp.json + CLAUDE.md enforcement)
├── ✅ Spec 028 — Single source of truth (triple-update pattern)
├── ✅ Spec 029 — Copier migration (from cookiecutter)
├── ✅ Spec 024 — /forge command (replaces /bootstrap + /sync)
├── ✅ Spec 025 — Interactive UI elements (Choice Blocks)
├── ✅ Spec 047 — Structured logging library
├── ✅ Spec 049 — Project-scoped insights engine
├── ✅ Spec 055 — Anthropic prompt caching
├── ✅ Spec 056 — Model tiering
└── ✅ Spec 057 — Command file compression

Phase 2: Async Review via NanoClaw (L2 → L3) ✅ DELIVERED (2026-03-14/15)
├── ✅ Spec 033 — Gate decision protocol with YubiKey MFA
├── ✅ Spec 034 — Persistent gate state
├── ✅ Spec 030 — NanoClaw adapter for FORGE
├── ✅ Spec 031 — Evidence capture tooling
├── ✅ Spec 032 — Session persistence / detached mode
├── ✅ Spec 050 — Hardware key safety, model detection & auth abstraction
├── ✅ Spec 053 — NanoClaw container deployment
└── ✅ Spec 054 — NanoClaw IPC gate bridge (OPERATIONAL)

Phase 3: Multi-Agent Swarms (L3 → L3+) ✅ SPECCED (2026-03-15)
├── ✅ Spec 040 — Multi-agent scheduler
├── ✅ Spec 041 — Cross-agent conflict detection
└── ✅ Spec 042 — Swarm budget management

Phase 4: Self-Improving Autonomy (L4) ✅ SPECCED (2026-03-15)
├── ✅ Spec 043 — Automated evolve loop runner
├── ✅ Spec 044 — Signal pattern analysis engine
├── ✅ Spec 045 — Spec proposal generation
└── ✅ Spec 046 — Autonomy config change protocol

Lane B: Compliance Engine ✅ ALL DELIVERED (2026-03-15)
├── ✅ Spec 035 — Compliance profile schema
├── ✅ Spec 036 — Bidirectional traceability matrix
├── ✅ Spec 037 — Configurable compliance gates
├── ✅ Spec 038 — Change impact analysis
├── ✅ Spec 039 — V&V report auto-generation
└── ✅ Spec 052 — Lane B spec immutability (sealing)

Post-Sprint Closed (sessions 005–012):
├── ✅ Spec 058 — Shared forge_source() utility library
├── ✅ Spec 059 — Cross-platform test plan template
├── ✅ Spec 060 — NanoClaw batch validation gate
├── ✅ Spec 061 — /skills revamp with workflow guidance
├── ✅ Spec 062 — Cross-platform path awareness
├── ✅ Spec 063 — Publications refresh & announcement articles
├── ✅ Spec 064 — PAL extraction and FORGE integration
├── ✅ Spec 065 — /forge stoke Copier migration
├── ✅ Spec 066 — Workspace write-access gate
├── ✅ Spec 067 — /forge stoke AI-assisted conflict resolution
├── ✅ Spec 068 — /forge stoke missing file restoration
├── ✅ Spec 069 — /forge stoke auto-commit
├── ✅ Spec 072 — /forge init path + legacy upgrade (was /forge light)
├── ✅ Spec 073 — Deferred first-session onboarding
├── ✅ Spec 074 — NanoClaw-FORGE bridge extraction
├── ✅ Spec 075 — /interview Socratic elicitation
├── ✅ Spec 076 — Multi-agent command portability
├── ✅ Spec 077 — User-level vs project-level split
├── ✅ Spec 078 — Role-based agent pipeline
├── ✅ Spec 079 — Skill auto-testing framework
├── ✅ Spec 080 — Context-aware skill auto-triggering
├── ✅ Spec 083 — Two-stage subagent review protocol
├── ✅ Spec 085 — Dynamic model router
├── ✅ Spec 086 — Auto-trigger /matrix status sync in /close
├── ✅ Spec 087 — Backlog dependency tracking and parallel batch detection
├── ✅ Spec 088 — Automated score verification
├── ✅ Spec 089 — Spec integrity SHA signatures
├── ✅ Spec 091 — Context engineering for slash commands
├── ✅ Spec 093 — Browser test automation and visual evidence capture
├── ✅ Spec 098 — Fix SC2046 in forge-orchestrate.sh
└── ✅ Spec 099 — Context-scoped role separation

Post-Sprint Closed (sessions 013–028, specs 100–136):
├── ✅ Spec 100 — Hook-enforced tool restrictions for role isolation
├── ✅ Spec 101 — Worktree path resolution guard
├── ✅ Spec 102 — Metrics rotation and retention
├── ✅ Spec 104 — Roadmap refresh
├── ✅ Spec 105 — Session start briefing
├── ✅ Spec 106 — Knowledge synthesis (/synthesize)
├── ✅ Spec 107 — Evolve loop documentation
├── ✅ Spec 108 — Cross-artifact relationship index
├── ✅ Spec 110 — Matrix auto-sync enhancements
├── ✅ Spec 111 — Command deduplication (.claude/ vs .forge/)
├── ✅ Spec 112 — Split /forge + lazy-load conditionals
├── ✅ Spec 113 — System prompt optimization
├── ✅ Spec 114 — DRY pass: scoring formula + light spec
├── ✅ Spec 115 — Shadow validation pattern
├── ✅ Spec 116 — Context anchoring in CLAUDE.md
├── ✅ Spec 117 — Spec kit bridge documentation
├── ✅ Spec 118 — Spec kit MCP integration
├── ✅ Spec 119 — Session handoff schema
├── ✅ Spec 121 — Bash script portability guard
├── ✅ Spec 123 — Context overflow resilience
├── ✅ Spec 124 — Context anchoring guide
├── ✅ Spec 125 — Long-running task patterns
├── ✅ Spec 126 — Supply chain security gate (/dependency-audit)
├── ✅ Spec 127 — ADR template and /decision command
├── ✅ Spec 128 — Cognitive debt guardrail
├── ✅ Spec 129 — Shadow validation first-class pattern
├── ✅ Spec 130 — CLI-first agent compatibility
├── ✅ Spec 131 — UX consolidation: /now hub, deprecations, /forge restructure
├── ✅ Spec 132 — Documentation cleanup, sync guard, quick reference
├── ✅ Spec 133 — Session identity and spec owner resolution
└── ✅ Spec 136 — Digest ingestion pipeline

Phase 5: Remaining Draft Specs (7 specs across 4 themes)
├── Multi-agent
│   └── Spec 134 — Multi-agent concurrent session model (score 33, draft)
├── Developer experience
│   └── Spec 135 — Review engagement canary (score 30, draft)
├── Compliance maturity
│   ├── Spec 103 — Git-signed audit trail for Lane B (score 26, draft)
│   └── Spec 090 — Shared team baselines and Copier presets (score 28, draft)
├── Knowledge management
│   ├── Spec 109 — Cross-project knowledge bridge (score 26, draft)
│   └── Spec 120 — DX metrics dashboard (score 25, draft)
└── Model strategy
    └── Spec 122 — Multi-vendor model strategy (score 23, draft)

Deprecated (11 specs — scope moved to NanoClaw, MCP servers, or separate products):
├── — Spec 004 — Isolated agent runtime (→ 004a + 004b)
├── — Spec 070 — (deprecated)
├── — Spec 071 — (deprecated)
├── — Spec 081 — Code graph integration (→ MCP server)
├── — Spec 082 — Persistent knowledge engine (→ MCP server)
├── — Spec 084 — FORGE IDE extension (→ separate repo)
├── — Spec 092 — Wide research parallelism (→ Claude Code feature)
├── — Spec 094 — Scheduled autonomous tasks (→ NanoClaw)
├── — Spec 095 — External agent runtime dispatch (→ NanoClaw)
├── — Spec 096 — Frictionless channel onboarding (→ NanoClaw)
└── — Spec 097 — FORGE web app evaluation (→ separate product)
```

---

## Phase 5 — Remaining Draft Specs
**Status: partially delivered** | 7 draft specs remain across 4 themes (6 original Phase 5 specs closed, 7 deprecated)

Most original Phase 5 specs have been delivered (100, 101, 102 closed) or deprecated (081, 082, 084, 092, 094, 095, 096, 097 → scope moved to NanoClaw, MCP servers, or separate products). Remaining draft specs span multi-agent coordination, developer experience, compliance maturity, and knowledge management.

### Theme 1: Multi-Agent Coordination
- **Spec 134** — Multi-Agent Concurrent Session Model (score 33): session isolation + role separation for concurrent agent work

### Theme 2: Developer Experience
- **Spec 135** — Review Engagement Canary (score 30): Van Halen M&M check — canary items in specs verify human reviewer engagement

### Theme 3: Compliance Maturity
- **Spec 103** — Git-Signed Audit Trail for Lane B (score 26): GPG-signed commits/tags at gate transitions for tamper-evident audit trails (IEC 61508, FDA 21 CFR Part 11)
- **Spec 090** — Shared Team Baselines and Copier Presets (score 28): org-wide configuration defaults and Copier preset distributions for team standardization

### Theme 4: Knowledge Management & Metrics
- **Spec 109** — Cross-Project Knowledge Bridge (score 26): cross-project knowledge sharing and pattern propagation
- **Spec 120** — DX Metrics Dashboard (score 25): developer experience metrics collection and visualization
- **Spec 122** — Multi-Vendor Model Strategy (score 23): support for non-Anthropic model providers

---

## NanoClaw Integration

[NanoClaw](https://nanoclaw.dev/) is the messaging-integrated AI agent runtime that bridges FORGE's autonomous agents with the human reviewer. It enters the picture in Phase 2 and becomes the primary orchestration layer by Phase 3.

### When agents contact humans

| Trigger | Evidence sent | Expected response |
|---------|--------------|-------------------|
| Gate decision (spec implemented) | Test output screenshot, diff summary, AC checklist | approve / reject with reason |
| Gate failure (tests fail, lint errors) | Error output, relevant code context | guidance / "retry" / "halt" |
| Budget threshold (80% consumed) | Budget breakdown, remaining work estimate | "continue" / "halt" / increase budget |
| Scope question (ambiguous requirement) | Spec excerpt, options analysis | choice selection |
| Kill switch triggered | State snapshot, audit log excerpt | "revert" / "preserve and halt" |
| Evolve loop proposal (Phase 4) | Signal patterns, draft spec summaries | approve / reject / modify |

### What evidence agents send

- **Screenshots**: Terminal output of test runs, build results, lint reports (captured via headless screenshot tools)
- **Diff summaries**: Condensed file-level change summaries with line counts
- **Test results**: Pass/fail counts, coverage delta, specific failure details
- **Videos** (Phase 3+): Recorded agent sessions for complex multi-step implementations, UI test recordings
- **Budget reports**: Time elapsed, tokens used, cost incurred, remaining budget

### Which channels

NanoClaw supports WhatsApp (native), Telegram, Slack, Discord, and Signal via its skills system. The human configures their preferred channel in NanoClaw — FORGE doesn't need to know which platform is used. FORGE sends structured messages to NanoClaw; NanoClaw routes them to the configured channel.

---

## Phase Timeline

Phases 1–4 were delivered in 3 days (2026-03-13 through 2026-03-15). Post-sprint work continued through 23 sessions (2026-03-13 through 2026-03-28), closing 120 total specs.

1. **Phase 1** ✅ **COMPLETE** (2026-03-13) — command chaining, gate auto-detection, auto-progression config (4 specs)
2. **Phase 2** ✅ **DELIVERED** (2026-03-14/15) — NanoClaw IPC bridge, YubiKey auth, persistent gate state, evidence capture (8 specs). IPC gate bridge operational on Telegram.
3. **Phase 3** ✅ **SPECCED** (2026-03-15) — multi-agent scheduler, conflict detection, swarm budget (3 specs). Template infrastructure in place; operational validation pending.
4. **Phase 4** ✅ **SPECCED** (2026-03-15) — automated evolve loop, signal analysis, spec proposals, config change protocol (4 specs). Signal analysis already operational — 5 specs auto-proposed from patterns.
5. **Phase 5** ⚡ **PARTIALLY DELIVERED** — 6 specs closed (100, 101, 102, 104, 105, 107), 7 deprecated (→ NanoClaw/MCP/separate products), 7 draft specs remain.

**Cross-cutting concerns** — all delivered: Spec Kit integration, MCP servers, Copier migration, `/forge` command, prompt caching, model tiering, structured logging, insights engine (11 specs).

**Post-sprint closed** (sessions 005–028): 62 specs covering `/forge stoke` upgrade pipeline (065–069), onboarding and portability (072–077), agent pipeline and review (078–080, 083), process automation (085–089, 091, 093, 098, 099), system prompt optimization (111–114), context anchoring (116, 124), knowledge synthesis (106, 108), supply chain security (126), ADRs (127), UX consolidation (131), and more.

**Lane B** (compliance engine) — all delivered: compliance profiles, traceability, gates, impact analysis, V&V reports, spec sealing (6 specs). The compliance engine is regulation-agnostic, with `eu-machinery` as the reference profile (EU 2023/1230 effective January 2027).

**Operational progression**: While all template infrastructure is delivered, full autonomy progression (L2 → L3 → L4) is gated by operational trust. L2 (supervised chaining) is the current daily operating level. L3/L4 capabilities activate as the system demonstrates reliability in consumer projects.

---

## Revision Log

- 2026-03-13: Initial roadmap created (Spec 016). Four phases defined: command chaining, async review via NanoClaw, multi-agent swarms, self-improving autonomy.
- 2026-03-13: Phase 1 marked COMPLETE (Specs 019–022). Added cross-cutting concerns section: Spec Kit integration, MCP documentation servers, single source of truth for spec status, /sync command + Copier migration, dual-lane architecture. Added Lane B dependency graph with EU Machinery Regulation 2023/1230 as north star. Added persistent gate state as Phase 2 prerequisite (discovered during Phase 1 signal analysis).
- 2026-03-13: Generalized Lane B from hardcoded IEC 61508/EU 2023/1230 to a regulation-agnostic compliance engine with pluggable compliance profiles. EU machinery becomes the reference profile, not the definition. Added compliance profile schema, example profiles (automotive, medical, fintech, internal), and profile-driven configurability for gates, artifacts, and MCP sources.
- 2026-03-13: Added liability protections: compliance profile verification gate (human sign-off on documentation sources), mandatory disclaimer on all compliance artifacts, and explicit "not a certification authority" language. FORGE assists qualified professionals — it does not replace them.
- 2026-03-15: Major update — all four phases delivered. Phase 2 (8 specs): NanoClaw IPC gate bridge operational on Telegram, YubiKey HMAC-SHA1 mutual auth implemented, persistent gate state, evidence capture. Phase 3 (3 specs): multi-agent scheduler, conflict detection, swarm budget — template infrastructure. Phase 4 (4 specs): automated evolve loop, signal pattern analysis, spec proposals, config change protocol — template infrastructure, signal analysis already operational. Cross-cutting (11 specs): Copier migration, prompt caching, model tiering, structured logging, insights engine. Lane B (6 specs): compliance profiles, traceability, gates, impact analysis, V&V reports, spec sealing. Dependency graph updated with all 57 closed spec numbers. 5 draft specs remain (058-062).
- 2026-03-19: Roadmap refresh (Spec 104). Updated current state: 89 closed, 13 draft, 106 total specs. Replaced stale "What's next" (9 specs, all now closed) with current 13 draft specs. Expanded dependency graph with 31 post-sprint closed specs (058–099). Added Phase 5 section with 5 strategic themes: developer experience, operational reliability, advanced autonomy, compliance maturity, knowledge management. Updated phase timeline.
- 2026-03-28: Docs refresh (Spec 137). Updated current state: 120 closed, 7 draft, 11 deprecated, 139 total spec entries across 23 sessions. Updated "What's next" (removed closed 131/132, added 134/135). Added specs 100–136 to dependency graph. Restructured Phase 5: 6 original specs closed, 7 deprecated (→ NanoClaw/MCP/separate products), 7 draft remain across 4 themes. Updated phase timeline. Added 24 new capabilities to "What works today".
