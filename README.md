# FORGE — Framework for Organized Reliable Gated Engineering

AI coding assistants lose context between sessions, drift from the original goal, and declare work done before it meets acceptance criteria. FORGE fixes that with specs, evidence gates, and a structured delivery process that remains reliable as agent autonomy increases.

## Mission

FORGE's mission is to make each individual developer the CEO of a continuously-optimizing development company. FORGE provides strategic advisors, executive staff, and auditable process at every step — but the developer decides exactly what happens, when, and why.

## Contents

- [Quickstart](#quickstart) — install and bootstrap in minutes
- [What is FORGE?](#what-is-forge) — the problem, the approach, how it works
- [MCP Documentation Servers](#mcp-documentation-servers) — optional doc servers
- [Architecture Overview](#architecture-overview) — layer model and module system
- [Key Concepts](#key-concepts) — specs, evidence gates, loops, lanes
- [Agent Runtime](#agent-runtime) — autonomy levels and NanoClaw integration
- [Contributing](#contributing) — how to contribute
- [Compliance Disclaimer](#compliance-disclaimer) — what FORGE is not
- [License](#license) — MIT

## Quickstart

### Prerequisites

FORGE requires Python 3.9+, Git, and [Copier](https://copier.readthedocs.io/) 9.0+. The install script detects and installs missing prerequisites automatically.

<details>
<summary>Manual prerequisite installation</summary>

```bash
pip install copier
```

**Windows** (Git Bash required for FORGE runtime scripts):
```powershell
# Scoop
scoop install git python && pip install copier shellcheck-py

# Or winget
winget install Git.Git && winget install Python.Python.3.12 && pip install copier shellcheck-py
```

Git for Windows includes Git Bash. The PowerShell wrappers (`.ps1`) auto-detect Git Bash and delegate.

</details>

### Install

One command to install FORGE — the script detects your environment and adapts:

```bash
# macOS / Linux / Git Bash on Windows
curl -fsSL https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.sh | bash

# Windows PowerShell
irm https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.ps1 | iex
```

The install script handles prerequisites (Python, Git, Copier), detects Claude Code, and provides environment-appropriate next steps. Safe to run multiple times.

> **IDE reload required:** If your IDE is already open when you run the install script, reload the window so it picks up the new `/forge-bootstrap` command (VS Code: `Ctrl+Shift+P` → "Developer: Reload Window").

### Bootstrap your project

**New project:**
```bash
mkdir my-project && cd my-project
# In Claude Code: run /forge-bootstrap
# Other IDEs: copier copy https://github.com/Renozoic-Foundry/forge-public.git .
```

**Existing project** (add FORGE to an existing repo):
```bash
cd my-existing-repo
# In Claude Code: run /forge-bootstrap
# Other IDEs: copier copy https://github.com/Renozoic-Foundry/forge-public.git .
```
FORGE files are added alongside your existing code. Copier prompts before overwriting any conflicting files.

**One-shot install + bootstrap:**
```bash
curl -fsSL https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.sh | bash -s -- --init my-project
```

### What happens after install

| Your environment | What the script does | Your next step |
|---|---|---|
| **Claude Code** | Installs prereqs + plants `/forge-bootstrap` command | Run `/forge-bootstrap` in any project |
| **Claude Code** + `--init` | Installs prereqs + bootstraps project | Run `/onboarding` in the project |

**Want the full walkthrough?** See the [Getting Started tutorial](docs/getting-started.md) — zero to first closed spec in a single session. Or read the [Concept Overview](docs/concept-overview.md) to understand what FORGE is and why it exists.

**Want to see the result?** See [docs/examples/hello-forge/](docs/examples/hello-forge/) for what a bootstrapped project looks like after `/forge init` and a first spec cycle.

<details>
<summary>Other AI IDEs (Cursor, Windsurf, Copilot, etc.)</summary>

| Your environment | What the script does | Your next step |
|---|---|---|
| **Other AI IDE** | Installs prereqs | `copier copy https://github.com/Renozoic-Foundry/forge-public.git my-project`, then open in your IDE — it reads `AGENTS.md` |
| **Private fork** | `bash install.sh --repo <url>` — same flow with git auth preflight | Same as above, using your fork URL |

**Manual path (power users):**
```bash
pip install copier
copier copy https://github.com/Renozoic-Foundry/forge-public.git my-project
cd my-project
```
Then open the project in your AI-assisted IDE and let your assistant read `AGENTS.md`.

</details>

FORGE works with any AI-assisted IDE. Not using Claude Code? See the collapsed section above for Cursor, Windsurf, Copilot, and manual paths.

### Keeping up to date

| What to update | Claude Code | Other IDEs |
|---|---|---|
| **FORGE framework** (install script, `/forge-bootstrap`) | Re-run the install script | Re-run the install script |
| **Your project** (commands, templates, process kit) | `/forge stoke` | `copier update` |

Framework updates install new versions of the bootstrap command. Project updates pull the latest template changes into your project — new commands, refined gates, better defaults — while preserving your customizations.

## What is FORGE?

FORGE is an opinionated development framework that synthesizes five foundational standards into a coherent workflow for human-AI collaborative software delivery. The underlying methodology — Evidence-Gated Iterative Delivery (EGID) — ensures every lifecycle transition requires demonstrable proof.

**The speed multiplier:** Traditional spec-driven development is thorough but slow. FORGE inverts that tradeoff — AI generates detailed specs from a brief description (objective, scope, acceptance criteria, test plan), then implements them with evidence at every gate. The human role shifts from writing documentation to reviewing and approving, where judgment adds the most value. At higher autonomy levels, AI can chain from spec creation straight through to validated closure — but by default, every AI-written spec is gated from implementation until a human approves it.

**The Solve/Evolve double-loop:** FORGE doesn't just deliver work — it learns from it. The **Solve Loop** (`/spec` → `/implement` → `/close`) delivers each change with evidence gates. The **Evolve Loop** captures signals from every session — errors, corrections, friction — and proposes process improvements as new specs. `/session` logs what happened. `/note` captures insights mid-work. `/evolve` reviews accumulated patterns and adapts the process. Static frameworks calcify; FORGE compounds. See [Design Philosophy](docs/design-philosophy.md) for the full treatment.

### Core framework (every project)

These capabilities are built into every FORGE project out of the box:

- **AI-generated specs** — Describe what you need; AI produces the full spec in seconds. Human approves; AI implements with evidence at every gate.
- **Evidence gates** — Every lifecycle transition requires proof. Structured PASS/FAIL outcomes. Gate failures produce actionable feedback.
- **KCS v6 double-loop learning** — Solve Loop delivers specs. Evolve Loop captures signals, analyzes patterns, and proposes process improvements automatically.
- **Role-separated agents** — 16 roles (Spec Author, Devil's Advocate, Implementer, Validator, CTO, CISO, CFO, CXO, COO, CCO, CQO, CEfO, CMO, CRO, CResO, Maverick Thinker) with runtime tool restrictions via `.claude/agents/`.
- **Scored backlog** — Priority formula ranks every spec. AI picks the highest-value work. Dependency tracking prevents blocked starts.
- **29 slash commands** — Full lifecycle coverage with command chaining and model tiering (Haiku for display, Sonnet for code).
- **Session logging and signal capture** — Every session ends with a log. Retro signals inform priority re-scoring.

### Enhancing features (opt-in)

Optional capabilities activated per-project based on needs. The core framework operates fully without any of these.

- **NanoClaw Messaging Bridge** — Async gate approvals via Telegram, WhatsApp, Slack. Agents work while you're away; you review on your phone. *For L3+ autonomy.*
- **Multi-agent swarms** — Parallel spec delivery with conflict detection and swarm budgets. *For high-throughput projects.*
- **OCI container isolation** — Role-scoped volume mounts for filesystem permission enforcement. *Alternative to default git worktree isolation.*

### Roadmap

These features are under active development and will be available in future releases:

- **Lane B Compliance Engine** — Pluggable compliance profiles for regulated industries (IEC 61508, EU 2023/1230, ISO 13485, IEC 62443). Bidirectional traceability, V&V reports, spec sealing. Designed for safety-critical firmware and medical device teams.
- **Hardware Authentication (PAL)** — YubiKey HMAC-SHA1 challenge-response for gate decisions. Cryptographic proof of human approval. Will be required for Lane B; optional for Lane A.

### Foundations

1. **KCS v6 (Knowledge-Centered Service)** — Double-loop learning: a Solve Loop for every spec, an Evolve Loop to improve the process itself. Signals (errors, insights, retro findings) are captured at lifecycle transitions and feed back into priority scoring.

2. **Stage-Gate (Cooper)** — Evidence gates at each lifecycle transition (`draft → in-progress → implemented → closed`). Gate failures produce structured feedback identifying what is missing. No status transition without demonstrable evidence.

3. **AAIF (Agentic AI Foundation, Linux Foundation 2025)** — `AGENTS.md` defines bounded autonomy, delegation contracts, prohibited actions, and signal capture responsibilities. The AI agent operates within explicit guardrails.

4. **Spec Kit** — Every change has a versioned spec with objective, scope, requirements, acceptance criteria, test plan, and revision log. Specs are rebuild guides — the codebase can be reconstructed from specs alone. Specs also serve as **context anchors**: living documents that persist decision context across AI sessions, team changes, and time. Rahul Garg's writing on [context anchoring](https://martinfowler.com/articles/reduce-friction-ai/context-anchoring.html) (2026, published on martinfowler.com) independently validated this pattern — FORGE has practiced it from the start.

5. **Copier** — Template-based project bootstrapping with upstream sync. Framework improvements propagate to all downstream projects via `copier update`.

### Autonomy levels

FORGE defines five autonomy levels (L0–L4), all supported. The default is L1 (human-gated). At L2+, the agent chains `/implement` → `/close` → `/implement next` cycles with the human watching at the terminal, intervening only on gate failures or decision points. L3–L4 enable fully async operation via NanoClaw messaging (enhancing feature, opt-in).

| Level | Name | Human role | Status |
|-------|------|-----------|--------|
| L0 | Manual | Human drives everything | Supported |
| L1 | AI-Assisted | AI implements, human gates every transition | Supported (default) |
| L2 | Supervised Auto-Chain | Commands auto-chain on success, human watches | **Supported (Phase 1 complete)** |
| L3 | Async Review | Agents run autonomously, human approves via messaging | Available via NanoClaw (opt-in) |
| L4 | Self-Improving | Agents propose process improvements, human approves weekly | Preview — requires NanoClaw |

## MCP Documentation Servers

FORGE uses [Model Context Protocol](https://modelcontextprotocol.io/) servers to ensure agents work from current documentation rather than stale training data.

- **Context7** — Versioned library/framework documentation matched to your project's dependencies
- **Fetch** (Anthropic official) — Any URL converted to agent-readable markdown on demand

MCP servers are declared in `.mcp.json` at the project root.

## Architecture Overview

```
your-project/
  .claude/
    commands/           # FORGE workflow commands (slash commands)
    settings.json       # IDE hooks (auto-test on edit)
  .forge/
    bin/                # Agent runtime scripts + PowerShell wrappers
      forge-orchestrate.sh/.ps1   # Multi-agent pipeline orchestrator
      forge-kill.sh/.ps1          # Kill switch — halt all agents
      forge-status.sh/.ps1        # Agent status query
    lib/                # Shared libraries (config, adapters, handoff, audit, budget)
    adapters/           # Runtime adapters (native, OCI) and agent adapters (generic, claude-code)
    templates/          # Handoff schema + role instruction templates
    Dockerfile          # Base image for OCI mode (extend for your stack)
    handoffs/           # Runtime: inter-agent handoff artifacts (gitignored)
    audit/              # Runtime: audit logs and PID registry (gitignored)
  CLAUDE.md             # Operating contract (framework + project-specific)
  AGENTS.md             # AAIF agent configuration + runtime config
  docs/
    process-kit/        # Runbooks, rubrics, checklists, templates
    specs/              # Versioned spec files
    sessions/           # Session logs, signals, scratchpad
    decisions/          # ADR-style architecture decisions
    backlog.md          # Scored and ranked spec backlog
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
- **Core vs enhancing**: Core framework (specs, gates, learning, commands) works standalone; enhancing features (compliance, NanoClaw, hardware auth) are opt-in

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

FORGE includes a multi-agent pipeline for L2+ autonomy levels. The orchestrator manages role-separated agents (Spec Author → Devil's Advocate → Implementer → Validator) with handoff artifacts and audit logging.

```bash
# Dry run — see the pipeline plan without executing
.forge/bin/forge-orchestrate.sh --spec 001 --dry-run

# Run the full pipeline
.forge/bin/forge-orchestrate.sh --spec 001

# Check agent status
.forge/bin/forge-status.sh

# Emergency halt — stop all agents
.forge/bin/forge-kill.sh
```

**Runtime modes:**
- **Native** (default) — git worktree isolation. No container runtime required. Note: no filesystem permission enforcement.
- **OCI** (opt-in) — container isolation with role-scoped volume mounts (`:ro`/`:rw`). Works with any OCI-compatible runtime: Rancher Desktop (dockerd), Podman, nerdctl, Docker Engine. Set `runtime.adapter: oci` in AGENTS.md.

On Windows, use the `.ps1` wrappers (e.g., `forge-orchestrate.ps1`) — they auto-detect Git Bash and delegate.

## Reference Implementation

FORGE was built using its own methodology — 302 specs across 73 sessions, validating the full lifecycle from draft through closure. The development history (specs, session logs, signals, ADRs) demonstrates the methodology in practice.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for prerequisites, development setup, spec lifecycle, and how to open a PR.

## Compliance Disclaimer

FORGE is a process framework, not a certification authority. Compliance features (Lane B profiles, traceability matrices, V&V reports) are aids for qualified professionals — they do not constitute regulatory assessments, certifications, or legal determinations of compliance. All generated artifacts must be reviewed and approved by qualified engineers before submission to certification authorities. See [concept-overview.md](docs/concept-overview.md) for details.

## License

MIT License — see [LICENSE](LICENSE).
