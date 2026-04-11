# Contributing to FORGE

FORGE is a living framework that improves through use. Downstream projects (projects bootstrapped from this template) are the primary source of framework improvements. This document explains how to set up, develop, test, and contribute changes.

## Prerequisites

Before contributing to FORGE you will need:

- **Python 3.9+** — `python3 --version`
- **Git** — `git --version`
- **Copier 9.0+** — `pip install copier`
- **Claude Code** (for testing slash commands) — install from [claude.ai/code](https://claude.ai/code)
- **shellcheck** (for validating bash scripts) — `pip install shellcheck-py` or `brew install shellcheck`

Windows users: use Git Bash for all shell operations. PowerShell wrappers are in `template/.forge/bin/*.ps1`.

## Development Setup

1. Clone the repo: `git clone https://github.com/bwcarty/forge-public`
2. No build step — FORGE is a Copier template (text files + bash scripts).
3. Test your changes by bootstrapping a fresh project:
   ```bash
   FORGE_TEST_DIR="${TMPDIR:-${TEMP:-/tmp}}/forge-test"
   copier copy . "$FORGE_TEST_DIR" --defaults
   test -f "$FORGE_TEST_DIR/.copier-answers.yml" && echo "PASS" || echo "FAIL"
   ```
4. Run bash validation: `bash scripts/validate-bash.sh`
5. Verify command sync: `bash scripts/validate-command-sync.sh`

See [CLAUDE.md](CLAUDE.md) for the full testing sequence.

## Spec Lifecycle

All changes to FORGE follow the spec-driven lifecycle:

1. Create a spec: `docs/specs/NNN-short-title.md` (use `docs/specs/_template.md`)
2. Set status `draft` → get it approved (inline via `/implement` or manually)
3. Implement — every file change traces to a spec
4. Close — run `/close NNN` to transition to `closed`

Status progression: `draft → in-progress → implemented → closed | deprecated`

The spec is the unit of work. No implementation without one.

## Testing

After any template change:
```bash
# Validate bash scripts
bash scripts/validate-bash.sh

# Validate .claude/commands mirror .forge/commands
bash scripts/validate-command-sync.sh

# Bootstrap a clean project and verify no errors
bash scripts/smoke-test-runtime.sh
```

Manual validation steps are in [`docs/process-kit/human-validation-runbook.md`](docs/process-kit/human-validation-runbook.md).

## Command Naming Guidelines

When adding or renaming a slash command:

1. **Check for ambiguity**: Does the command name imply modification of external or shared systems? If so, declare explicit scope limits in the opening line of the command file. Example: a command named `/deploy` must open with "**Scope**: operates on the current project directory only — does not push to any remote system."
2. **Use the canonical form**: `/forge init` not `/forge light`; `/forge stoke` not `/forge-stoke`. Dispatch aliases are a source of confusion — prefer one canonical name.
3. **Mirror to both locations**: Every command file must exist in both `template/.claude/commands/` and `template/.forge/commands/` with identical content.
4. **Update `update-manifest.yaml`**: If you add, remove, or rename a command file, update `template/.forge/update-manifest.yaml` to classify it in `framework.paths`, `removed.paths`, or `obsolete.mappings` as appropriate.

## Upstream Learning Pipeline

FORGE's power comes from its feedback loops. When you discover something in your project that should be part of the framework itself, that learning flows upstream through one of three channels:

### 1. Signal Promotion

When a signal captured via `/close` or `/note` in your project reveals a **framework-level improvement**, promote it:

1. Open an issue with the `signal-promotion` label
2. Include the original SIG-NNN entry from your project's `docs/sessions/signals.md`
3. Describe the proposed framework change (which file, what to add/modify)

### 2. Error Pattern Sharing

When an error pattern recurs across multiple specs or projects, it should become a **framework-level guardrail**:

1. Open an issue with the `error-pattern` label
2. Include all related error entries (EA-NNN or SIG-NNN)
3. Propose a specific prevention mechanism

### 3. Insight Propagation

When a CI-NNN insight improves a command or template in your project, propagate upstream:

1. Open a PR against the FORGE repo
2. Apply the change to the Copier template files
3. Reference the original insight in the PR description
4. Ensure the change is domain-neutral

## Contribution Checklist

Before submitting any upstream contribution:

- [ ] Change is **domain-neutral** — no project-specific names, paths, or commands
- [ ] All template files retain `# Framework: FORGE` header
- [ ] `<!-- customize -->` markers are used at project-specific extension points
- [ ] Copier variables (e.g. `{{ project_name }}`) are used where appropriate in `.jinja` files
- [ ] Change has been tested via `copier copy` (see Testing section)
- [ ] PR description includes provenance (which signal/error/insight prompted this)
- [ ] Shellcheck passes on any modified `.sh` files

## Code of Conduct

Be constructive. Every contribution should make the framework better for all users. If in doubt about whether something belongs in FORGE vs. your project, open a discussion issue first.

## License

By contributing to FORGE, you agree that your contributions will be licensed under the MIT License.
