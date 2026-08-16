# FORGE — Framework for Organized Reliable Gated Engineering
<!-- Last verified: 2026-08-06 -->

AI coding assistants lose context between sessions, drift from the original goal, and declare work done before it meets acceptance criteria. FORGE fixes that with specs, evidence gates, and a structured delivery process that remains reliable as agent autonomy increases.

## Mission

FORGE's mission is to make each individual developer the CEO of a continuously-optimizing development company. FORGE provides strategic advisors, executive staff, and auditable process at every step — but the developer decides exactly what happens, when, and why.

**New here?** The [4-command starter set](docs/QUICK-REFERENCE.md#core-commands) covers
everything you need for a first session, and the [glossary](docs/team-guide.md#glossary)
defines every FORGE-specific term you'll run into below.

## Contents

- [Quickstart](#quickstart) — install and bootstrap in minutes
- [What's new](#whats-new) — recent FORGE updates by audience
- [What is FORGE?](#what-is-forge) — the problem, the approach, how it works
- [MCP Documentation Servers](#mcp-documentation-servers) — optional doc servers
- [Architecture Overview](#architecture-overview) — layer model and module system
- [Key Concepts](#key-concepts) — specs, evidence gates, loops, lanes
- [Agent Runtime](#agent-runtime) — autonomy levels and the multi-agent pipeline
- [Contributing](#contributing) — how to contribute
- [Compliance Disclaimer](#compliance-disclaimer) — what FORGE is not
- [License](#license) — MIT

## Quickstart

FORGE is delivered as a **signed Claude Code plugin**. The plugin is the runtime — it ships
every slash command, agent role, skill, and hook. Your project keeps only its own data (specs,
sessions, process docs); the framework updates through the plugin, not through file copies.

### Prerequisites

- **Claude Code** (recommended path): [Claude Code](https://claude.ai/code) and Git. That's it —
  no Python, no template engine.
- **Other AI IDEs** (Cursor, Windsurf, Copilot, …): the pinned-checkout runtime path applies
  (Git only — clone the framework once at a release tag and point `~/.forge/runtime-root` at it;
  see the collapsed cross-IDE section below).

### Install the plugin

```bash
claude plugin marketplace add Renozoic-Foundry/forge-public
```

then, inside Claude Code:

```
/plugin install forge@forge
```

Or directly from a `forge-public` checkout:

```bash
git clone https://github.com/Renozoic-Foundry/forge-public.git
cd forge-public
claude plugin install ./
```

### Bootstrap your project

In Claude Code, from your project (new or existing):

```
/forge init
```

`/forge init` detects your situation and adapts: a **new/empty directory** gets the plugin-native
project scaffold (specs, sessions, backlog, `AGENTS.md`/`CLAUDE.md`, quick reference — no Copier
involved); an **existing repo** gets FORGE's process files added alongside your code; a
**pre-plugin FORGE project** is offered the upgrade path. Then run `/forge onboarding` — the one-time
guided setup that configures stack, autonomy, and features — and `/now` to get your first
recommended action.

### What happens after install

| Your environment | Install | Bootstrap | First session |
|---|---|---|---|
| **Claude Code** | `/plugin install forge@forge` | `/forge init` | `/forge onboarding`, then `/now` |
| **Other AI IDE** | — (plugin is Claude Code-specific) | Copier scaffold (collapsed section below) | Open the project; your assistant reads `AGENTS.md` |

**Want the full walkthrough?** See the [Getting Started tutorial](docs/getting-started.md) — zero to first closed spec in a single session. Or read the [Concept Overview](docs/concept-overview.md) to understand what FORGE is and why it exists.

**Want to see the result?** See [docs/examples/hello-forge/](docs/examples/hello-forge/) for what a bootstrapped project looks like after `/forge init` and a first spec cycle.

<details>
<summary>Other AI IDEs and the legacy Copier path</summary>

**Cross-IDE runtime (Spec 576 — the primary non-Claude path):** point a user-level, pinned
checkout of the framework at your projects — the repo stays as clean as a plugin consumer's:

```bash
git clone https://github.com/Renozoic-Foundry/forge-public.git ~/forge-runtime
git -C ~/forge-runtime checkout <release-tag>
echo "$HOME/forge-runtime" > ~/.forge/runtime-root
```

Every scaffolded project ships two thin launchers (`bin/forge`, `bin\forge.ps1`) resolving the
chain `CLAUDE_PLUGIN_ROOT → FORGE_RUNTIME_ROOT → ~/.forge/runtime-root → project-local` — other
AI agents read `AGENTS.md` and invoke `bin/forge <command>`; non-AI developers get
`bin/forge now|status|list`. Optionally record `forge.runtime.pin: <tag>` in the project's
AGENTS.md; the launcher warns when a teammate's checkout drifts from the pin.

(The legacy full-template Copier render was removed in v4.0.0 — Spec 558. `/forge init` is the
scaffolder. Classic Copier-rendered projects remain supported in place on ≤v3.x releases; their
opt-in on-ramp is `forge stoke --to-plugin` — see the
[migration decision guide](docs/process-kit/migration-decision-guide.md).)

(The legacy `install.sh` / `install.ps1` bootstrap scripts and their `forge-bootstrap.md` guide
were unpublished with the Copier surface in v4.0.0 — they rendered the deleted template; ≤v3.x
tags still carry them.) Not sure which path your project needs? Run `/forge doctor` — it detects
the state and offers the mapped fix
([migration decision guide](docs/process-kit/migration-decision-guide.md)).

**Security overrides (consent-required):**

Overrides of `test_command`, `lint_command`, `harness_command`, or any `include_*` security
toggle resolve through the live consent gate on every `/forge stoke` apply (Spec 591) — the
gate asks in-session and never persists consent. (The former render-time `copier copy --data`
consent shape was removed with the Copier surface in v4.0.0 — Spec 558.)

</details>

### Keeping up to date

| What to update | Claude Code (plugin) | Legacy Copier projects (≤v3.x) |
|---|---|---|
| **FORGE framework** (commands, agents, skills, hooks) | Update the plugin: re-run `/plugin install forge@forge` (marketplace) or `claude plugin install ./` from a refreshed checkout | Stay on ≤v3.x tooling, or migrate via `forge stoke --to-plugin` |
| **Your project's scaffold files** (process kit, templates) | `/forge stoke` (content-merge engine) | ≤v3.x `/forge stoke`; the `copier update` path was removed in v4.0.0 |

Framework behavior always comes from the installed plugin version. Generated reference docs
(quick reference, command reference) carry a provenance header naming the source version and a
revision-history section, so you can always tell what you're running.

## What's new

Recent changes since the last published refresh — split by audience. Each item cites the closed spec for traceability.

### User-facing changes

- **The public install route works end-to-end** — the shipped `/forge init` front door is fully plugin-native; the stale Copier-era scaffolder that v4.0.0 left in the public artifact was replaced, and overlay staleness is now gated at release time (Spec 635).
- **`/forge stoke` merges only FORGE-owned files** — the update path consults the ownership manifest and never sweeps your project's own files into a framework merge (Spec 636).
- **Versioned doctrine delivery** — consumer `AGENTS.md`/`CLAUDE.md` files carry a delimited, version-stamped authorization-core block generated from the framework's own doctrine; `/forge doctor` reports drift and hand-edit conflicts read-only (Spec 640).
- **Honest autonomy levels** — L3/L4 descriptions now state exactly what they buy (chain continuation while gates pass); `/close` and `git push` remain operator actions at every level (Spec 649).
- **`/test` runs your configured test command** — the project's configured `test_command` is honored instead of assuming Python (Spec 651).
- **`bin/forge` launcher correctness** — status crash fixed, doctor path corrected, PowerShell doctor added, exit codes aligned across shells (Spec 645).
- **Argument hints in the command picker + consistent bare-command menus** — every parameterized FORGE command shows its subcommands/flags in Claude Code's autocomplete (e.g. `/forge` shows `[init|stoke|status|doctor|update|…]`), and bare invocations print an annotated usage menu instead of guessing (Spec 626).
- **Install FORGE as a Claude Code plugin** — the command, agent, skill, and hook payload installs from the marketplace or directly from a checkout with `claude plugin install ./`. Plugin-primary distribution replaced the Copier template surface in v4.0.0 (Specs 463, 487–491, 558).

### Backend & process changes

- **Release machinery hardened** — content-sync preflight on the cutter (Spec 628), payload EOL pinning and working-tree renormalization (Specs 629, 634), release-safety gates added to the PowerShell cutter (Spec 638), CI acceptance tests that exercise the final artifact rather than the source tree (Specs 639, 653).
- **Payload verifier integrity** — the plugin payload verifier no longer loads its verification algorithm from the payload it verifies (Spec 631).
- **Commit hygiene on brownfield repos** — `/forge onboarding` and `/configure` no longer sweep unrelated work into their commits (Specs 647, 668).
- **Model & effort policy** — effort-before-model guidance codified; role/model consistency is checked mechanically (Spec 648).
- **Consensus proportionality** — review depth scales with a spec's risk and novelty instead of running full-depth for every spec (Spec 666).
- **Guard-family apply flow restored** — protected-file specs are implementable again via a uniform patch handoff with a fail-closed authority guard (Spec 667).

## What is FORGE?

FORGE is an opinionated development framework that synthesizes five foundational standards into a coherent workflow for human-AI collaborative software delivery. The underlying methodology — Evidence-Gated Iterative Delivery (EGID) — ensures every lifecycle transition requires demonstrable proof.

**The speed multiplier:** Traditional spec-driven development is thorough but slow. FORGE inverts that tradeoff — AI generates detailed specs from a brief description (objective, scope, acceptance criteria, test plan), then implements them with evidence at every gate. The human role shifts from writing documentation to reviewing and approving, where judgment adds the most value. At higher autonomy levels, AI can chain from spec creation straight through to validated closure — but by default, every AI-written spec is gated from implementation until a human approves it.

**The Solve/Evolve double-loop:** FORGE doesn't just deliver work — it learns from it. The **Solve Loop** (`/spec` → `/implement` → `/close`) delivers each change with evidence gates. The **Evolve Loop** captures signals from every session — errors, corrections, friction — and proposes process improvements as new specs. `/session` logs what happened. `/note` captures insights mid-work. `/evolve` reviews accumulated patterns and adapts the process. Static frameworks calcify; FORGE compounds. See [Design Philosophy](docs/design-philosophy.md) for the full treatment.

### Core framework (every project)

These capabilities are built into every FORGE project out of the box:

- **AI-generated specs** — Describe what you need; AI produces the full spec in seconds. Human approves; AI implements with evidence at every gate.
- **Evidence gates** — Every lifecycle transition requires proof. Structured PASS/FAIL outcomes. Gate failures produce actionable feedback.
- **KCS v6 double-loop learning** — Solve Loop delivers specs. Evolve Loop captures signals, analyzes patterns, and proposes process improvements automatically.
- **Role-separated agents** — 17 roles (Spec Author, Devil's Advocate, Implementer, Validator, Maverick Thinker, Competitor, CTO, CISO, CFO, CXO, COO, CCO, CQO, CEfO, CMO, CRO, CResO) with runtime tool restrictions via `.claude/agents/`.
- **Scored backlog** — Priority formula ranks every spec. AI picks the highest-value work. Dependency tracking prevents blocked starts.
- **30 slash commands** — Full lifecycle coverage with command chaining. Model tiering is advisory; the IDE model picker is the real selector (Spec 316). See [command reference](docs/command-reference.md) for the full list.
- **Session logging and signal capture** — Every session ends with a log. Retro signals inform priority re-scoring.

### Enhancing features (opt-in)

Optional capabilities activated per-project based on needs. The core framework operates fully without any of these.

- **Multi-agent swarms** — Parallel spec delivery with conflict detection and swarm budgets. *For high-throughput projects.*
- **OCI container isolation** — Role-scoped volume mounts for filesystem permission enforcement. *Alternative to default git worktree isolation.*

### Roadmap

Planned or deferred — not part of the supported feature set in this release. See [docs/roadmap.md](docs/roadmap.md) for the full shipped/preview/deferred classification.

- **Lane B Compliance Engine** — Pluggable compliance profiles for regulated industries (IEC 61508, EU 2023/1230, ISO 13485, IEC 62443). Bidirectional traceability, V&V reports, spec sealing. Lane-gate scaffolding exists in the command bodies; the engine itself requires additional validation before it ships.

### Foundations

FORGE synthesizes five foundations — **KCS v6** double-loop learning, **Stage-Gate** evidence
gates, **AAIF** bounded autonomy, **Spec Kit** persistent specs-as-context-anchors, and
**plugin-primary distribution**. The canonical definition (why these five, what each prevents,
and how they interlock) lives in
[Design Philosophy § Five Foundations](docs/design-philosophy.md#five-foundations--why-these-five-and-how-they-interlock)
— defined once so the lists cannot drift.

### Autonomy levels

FORGE defines five autonomy levels (L0–L4), all supported. The default is L1 (human-gated). At L2+, the agent chains `/implement` → `/close` → `/implement next` cycles, pausing at decision points; at L3+ it keeps chaining without a per-gate "continue?" pause while gates pass. What no level changes: authorization gates apply at every level — `/close` is operator-invoked and every `git push` raises an in-session approval prompt, at L0 and L4 alike.

| Level | Name | Human role | Status |
|-------|------|-----------|--------|
| L0 | Full Manual | Human drives everything; agent advises only | Supported |
| L1 | Human-Gated | AI implements, human gates every transition | Supported (default) |
| L2 | Supervised Autonomy | Commands auto-chain on success, human watches at decision points | **Supported** |
| L3 | Trusted Autonomy | Agent chains while gates pass, without per-gate pauses; the operator still invokes `/close` and approves every push | Supported |
| L4 | Full Autonomy | Adds spec-creation chaining; kill switch and budget ceilings are hard stops; `/close` stays operator-invoked | Supported (scheduled execution off by default) |

## MCP Documentation Servers

FORGE uses [Model Context Protocol](https://modelcontextprotocol.io/) servers to ensure agents work from current documentation rather than stale training data.

- **Context7** — Versioned library/framework documentation matched to your project's dependencies
- **Fetch** (Anthropic official) — Any URL converted to agent-readable markdown on demand

MCP servers are declared in `.mcp.json` at the project root.

## Architecture Overview

The framework runtime lives in the installed plugin; your repository keeps only its own data. `/forge init` scaffolds the project files below, and `claude plugin update` refreshes the framework without touching your repo.

```
your-project/                       # everything here is yours — scaffolded by /forge init
  AGENTS.md                         # AAIF agent operating contract + runtime config
  CLAUDE.md                         # Claude-specific addenda (imports AGENTS.md)
  bin/forge, bin/forge.ps1          # thin launchers — resolve the installed runtime for non-Claude agents and CI
  docs/
    specs/                          # versioned spec files (+ README index, CHANGELOG)
    sessions/                       # session logs, signals, scratchpad
    process-kit/                    # runbooks, rubrics, checklists
    QUICK-REFERENCE.md              # generated command quick reference
    backlog.md                      # scored and ranked spec backlog
  .forge/
    ownership.yaml                  # FORGE-owned vs project-owned partition (drives /forge stoke merges)
    state/                          # runtime state markers (gitignored)

<plugin install>/forge/<version>/   # the framework — delivered and updated as a signed plugin
  .claude/commands|agents|skills|hooks   # slash commands, role definitions, skills, session hooks
  .forge/bin|lib|templates               # runtime scripts, shared libraries, role + handoff templates
```

## Key Concepts

- **Two hard rules**: (1) Every change has a spec. (2) Every session has a log.
- **AI-generated specs**: Describe what you need in a few sentences; AI produces the full spec. Human approves before implementation begins.
- **Spec lifecycle**: `draft → in-progress → implemented → closed`
- **Evidence gates**: Each transition requires demonstrable proof (structured `GATE [name]: PASS/FAIL` outcomes)
- **Spec approval gate**: By default, every AI-written spec requires human approval before implementation — configurable per autonomy level
- **Change lanes**: `hotfix`, `small-change`, `standard-feature`, `process-only`
- **Signal capture**: Errors, insights, and retro findings are logged and inform priority scoring
- **Command chaining**: `/implement` → `/close` → `/implement next` auto-chains on gate success (L2+)
- **Core vs enhancing**: Core framework (specs, gates, learning, commands) works standalone; enhancing features (multi-agent swarms, OCI isolation, compliance profiles) are opt-in

### Why structure?

Long-running AI agents fail in predictable ways — and the fix is the environment, not the model. This is **harness engineering**: reliability comes from architecture, not intelligence.

| Failure mode | What happens | FORGE mitigation |
|---|---|---|
| **Context decay** | Agent loses track over long sessions | Session logs + structured handoff schemas |
| **Goal drift** | Agent wanders from the original objective | Spec gates — every action ties back to a spec |
| **Premature completion** | Agent declares "done" too early | Evidence gates in `/close` — no status transition without proof |
| **Self-evaluation bias** | Agent overrates its own output | Scoring rubric + Devil's Advocate role + external review criteria |

FORGE's structures aren't process overhead — they're the harness that makes autonomous delivery reliable.

## Agent Runtime

FORGE includes a multi-agent pipeline for L2+ autonomy levels. The orchestrator manages role-separated agents (Spec Author → Devil's Advocate → Implementer → Validator) with handoff artifacts and audit logging. You drive it through commands — the pipeline's orchestration, status, and kill-switch scripts ship inside the installed plugin's payload, not in your repository:

```
/parallel 101 102        # deliver independent specs in parallel git worktrees
/scheduler               # dependency-aware multi-agent scheduling
/forge status            # pipeline/project status (bin/forge status outside Claude Code)
```

**Runtime modes:**
- **Native** (default) — git worktree isolation. No container runtime required. Note: no filesystem permission enforcement.
- **OCI** (opt-in) — container isolation with role-scoped volume mounts (`:ro`/`:rw`). Works with any OCI-compatible runtime: Rancher Desktop (dockerd), Podman, nerdctl, Docker Engine. Set `runtime.adapter: oci` in AGENTS.md.

On Windows, `bin\forge.ps1` mirrors `bin/forge` — it auto-detects Git Bash and delegates.

## Reference Implementation

FORGE was built using its own methodology — 700 specs across 193 sessions (2026-03-13 through 2026-08-08), validating the full lifecycle from draft through closure. The development history (specs, session logs, signals, ADRs) demonstrates the methodology in practice.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for prerequisites, development setup, spec lifecycle, and how to open a PR. The canonical source repository is [Renozoic-Foundry/forge-public](https://github.com/Renozoic-Foundry/forge-public).

## Security

To report a vulnerability, use GitHub's **private vulnerability reporting** on [Renozoic-Foundry/forge-public](https://github.com/Renozoic-Foundry/forge-public) (Security tab → Report a vulnerability). Do not open a public issue for security reports. See [SECURITY.md](SECURITY.md) for the full policy and response timelines.

## Compliance Disclaimer

FORGE is a process framework, not a certification authority. Compliance features (Lane B profiles, traceability matrices, V&V reports) are aids for qualified professionals — they do not constitute regulatory assessments, certifications, or legal determinations of compliance. All generated artifacts must be reviewed and approved by qualified engineers before submission to certification authorities. See [concept-overview.md](docs/concept-overview.md) for details.

## License

MIT License — see [LICENSE](LICENSE).
