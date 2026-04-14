# Getting Started with FORGE

This tutorial walks you from zero to your first closed spec in a single short session.

FORGE is a project framework that gives AI-assisted development a structured delivery process — spec-driven, evidence-gated, and designed to remain reliable as agent autonomy increases.

The underlying methodology is Evidence-Gated Iterative Delivery (EGID). You will complete one full Solve Loop cycle: create a spec, implement it, and close it.

---

## Prerequisites

Before starting, ensure these are installed:

- **Python 3.9+** — required by Copier
- **Git** — version control
- **Copier 9.0+** — template engine (`pip install copier`)
- **An AI IDE** — Claude Code is recommended, but any AI assistant that reads `AGENTS.md` works

> **Note:** On Windows, use Git Bash or WSL for the bash commands in this tutorial. PowerShell is supported for the install step but not for all FORGE commands.

---

## Step 1 — Install FORGE

Run the one-liner install script for your platform.

**bash (macOS / Linux / Git Bash on Windows):**

```bash
curl -fsSL https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.sh | bash
```

**PowerShell (Windows):**

```powershell
irm https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.ps1 | iex
```

The install script adds FORGE's slash commands to your Claude Code configuration. It does not modify your project files.

> **Warning:** If your IDE is already open, reload the window after running the install script to pick up the new commands.

---

## Step 2 — Bootstrap a project

Create a new project from the FORGE template using Copier:

```bash
copier copy https://github.com/Renozoic-Foundry/forge-public.git my-project
```

Copier will prompt you for project details (name, description, etc.) and then generate the project scaffold. The resulting directory includes:

- `CLAUDE.md` — project instructions for your AI assistant
- `AGENTS.md` — agent role definitions and capabilities
- `docs/specs/` — where specs live
- `docs/sessions/` — session logs
- `docs/process-kit/` — scoring rubric, runbook, checklists
- `.forge/` — FORGE configuration and module manifests
- `.claude/commands/` — slash commands (`/implement`, `/close`, `/spec`, etc.)

Copier also creates `.copier-answers.yml` in the project root. This file records your template answers and enables future updates via `copier update`.

```bash
cd my-project
```

---

## Step 3 — Create a spec

Every change in FORGE starts with a spec — a versioned document that captures the objective, scope, acceptance criteria, and test plan. Open your AI IDE in the project directory and run:

```
/spec "add a --version flag to configlint"
```

The AI assistant generates a spec file in `docs/specs/` containing:

- **Objective** — what the change accomplishes and why
- **Scope** — what is in and out of scope
- **Requirements** — the specific deliverables
- **Acceptance criteria** — measurable conditions that define "done"
- **Test plan** — how to verify the change works

The spec is assigned a number (e.g., `001`) and starts in `draft` status. The assistant may ask clarifying questions before finalizing.

> **Note:** For a complete example of what a finished spec looks like, see the [hello-forge example](examples/hello-forge/docs/specs/001-hello-world.md).

---

## Step 4 — Implement the spec

With the spec created, run:

```
/implement 001
```

Replace `001` with your actual spec number.

The AI assistant reads the spec and begins implementation. During this process, it:

1. Reads the spec's requirements and acceptance criteria
2. Makes the code changes described in the spec
3. Runs tests defined in the test plan
4. Produces evidence gate outcomes — structured PASS/FAIL results for each acceptance criterion

Evidence gates are hard stops that require demonstrable proof before a spec can proceed. Each gate produces a verifiable outcome, not just an assertion. If a gate fails, the assistant reports what went wrong and what needs to change.

When implementation completes, the spec transitions to `implemented` status.

---

## Step 5 — Close the spec

After implementation, the operator reviews the results and closes the spec:

```
/close 001
```

During close, the operator:

1. Reviews the evidence gate results from implementation
2. Confirms all deliverables match the acceptance criteria
3. Approves the spec transition from `implemented` to `closed`

The close process also captures signals — observations about what worked well, what friction occurred, and what process improvements to consider. These signals feed the Evolve Loop, where FORGE's own process improves over time.

> **Note:** Closing a spec is a human decision. FORGE does not auto-close specs — the operator retains final authority over what ships.

---

## What you completed

You just ran one full Solve Loop:

1. **Spec** — defined the change with objective, scope, and acceptance criteria
2. **Implement** — built it with evidence gates verifying each criterion
3. **Close** — reviewed, approved, and captured process signals

This cycle repeats for every change, whether it is a one-line fix or a multi-week feature. The change lane determines how much ceremony each spec requires.

---

## Next steps

- [Concept overview](concept-overview.md) — how FORGE works and why it is structured this way
- [Command reference](command-reference.md) — every slash command with usage and examples
- [FAQ](faq.md) — common questions about adoption, AI compatibility, and process overhead

---

*Last verified against Spec 213 on 2026-04-11.*
