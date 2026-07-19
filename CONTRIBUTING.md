# Contributing to FORGE

FORGE is a living framework that improves through use. Downstream projects (projects bootstrapped from this template) are the primary source of framework improvements. This document explains how to set up, develop, test, and contribute changes.

> **Working on a team that uses FORGE?** If you're a developer in a project that uses FORGE (not contributing to the FORGE framework itself), see [Team Guide](docs/team-guide.md) — it explains specs, PR reviews, and how to make changes without FORGE commands.

## Contents

- [Prerequisites](#prerequisites) — what you need
- [Development Setup](#development-setup) — clone and test
- [Spec Lifecycle](#spec-lifecycle) — how changes flow
- [Testing](#testing) — Copier bootstrap and validation
- [Command Naming Guidelines](#command-naming-guidelines)
- [Upstream Learning Pipeline](#upstream-learning-pipeline) — how improvements flow back
- [Contributing from a Consumer Project](#contributing-from-a-consumer-project)
- [Contribution Checklist](#contribution-checklist) — before you submit
- [Pull Request Review](#pull-request-review) — what reviewers check

## Prerequisites

> **This section is the single source for FORGE tool-version pins** (Spec 572). Consumer docs
> intentionally do not restate versions — plugin consumers need only Claude Code + Git; the pins
> below apply to framework maintainers and the legacy Copier scaffold path.

Before contributing to FORGE you will need:

- **Python 3.10+** — `python3 --version` (floor enforced by the `forge-py` runtime wrapper)
- **Git** — `git --version`
- **Copier 9.4.0+** — `pip install copier` (floor enforced by `_min_copier_version` in `copier.yml`; legacy scaffold path only)
- **Claude Code** (for testing slash commands and the plugin payload) — install from [claude.ai/code](https://claude.ai/code)
- **shellcheck** (for validating bash scripts) — `pip install shellcheck-py` or `brew install shellcheck`

Windows users: use Git Bash for all shell operations. PowerShell wrappers are in `template/.forge/bin/*.ps1`.

## Development Setup

1. Clone the repo: `git clone https://github.com/Renozoic-Foundry/forge-public`
2. No build step — FORGE is a Copier template (text files + bash scripts).
3. Test your changes by bootstrapping a fresh project:
   ```bash
   FORGE_TEST_DIR="${TMPDIR:-${TEMP:-/tmp}}/forge-test"
   copier copy . "$FORGE_TEST_DIR" --defaults
   test -f "$FORGE_TEST_DIR/.copier-answers.yml" && echo "PASS" || echo "FAIL"
   ```
4. Run bash validation: `bash scripts/validate-bash.sh`
5. Verify generated-surface parity (repo-root `.forge/` canonical → plugin payload + `template/`): `bash .forge/bin/forge-parity.sh --check`

See `CLAUDE.md` (in your bootstrapped project) for the full testing sequence.

## Spec Lifecycle

All changes to FORGE follow the spec-driven lifecycle:

1. Create a spec: `docs/specs/NNN-short-title.md` (use `docs/specs/_template.md`)
2. Set status `draft` → get it approved (inline via `/implement` or manually)
3. Implement — every file change traces to a spec
4. Close — run `/close NNN` to transition to `closed`

Status progression: `draft → in-progress → implemented → closed | deprecated`

The spec is the unit of work. No implementation without one.

## Testing

**Fast matrix** — run after any change (all three are green on a clean checkout):
```bash
# Shellcheck across all runtime bash scripts
bash scripts/validate-bash.sh

# Generated-surface parity: canonical source → plugin payload, template mirrors,
# skills, AND generated reference docs (quick/command/config references — Spec 571)
bash .forge/bin/forge-parity.sh --check

# Public-doc style/consistency/deprecated-command validation
bash scripts/validate-public-docs.sh
```

**Full matrix** — additionally, before a release or after template/scaffold changes:
```bash
# Copier render smoke test (legacy scaffold path)
bash scripts/smoke-test-template.sh

# Bootstrap a clean project and exercise the runtime pipeline
bash scripts/smoke-test-runtime.sh

# Plugin payload parity + manifest schema
bash .forge/bin/plugin-parity-check.sh
bash .forge/bin/check-plugin-manifest.sh
```

If you changed a generated reference doc's canonical sources, regenerate before committing:
`scripts/gen-command-reference.sh --write`, `scripts/gen-quick-reference.sh --write`,
`.forge/bin/forge-py scripts/gen-agents-config-reference.py --write` — parity `--check` fails on
stale generated docs, and the publish pipeline refuses to sync them.

Manual validation steps are in `docs/process-kit/human-validation-runbook.md` (available after bootstrapping a project from this template).

## Command Naming Guidelines

When adding or renaming a slash command:

1. **Check for ambiguity**: Does the command name imply modification of external or shared systems? If so, declare explicit scope limits in the opening line of the command file. Example: a command named `/deploy` must open with "**Scope**: operates on the current project directory only — does not push to any remote system."
2. **Use the canonical form**: `/forge init` not `/forge light`; `/forge stoke` not `/forge-stoke`. Dispatch aliases are a source of confusion — prefer one canonical name.
3. **Author in the canonical source, then regenerate**: Command files live in the repo-root `.forge/commands/` single source. The plugin payload (`.claude/commands/`) and the `template/` Copier surface are **generated downstream** — never hand-edit the generated copies. After changing a canonical command, run `bash .forge/bin/forge-parity.sh` to regenerate the downstream surfaces and `bash .forge/bin/forge-parity.sh --check` to verify parity.
4. **Update `update-manifest.yaml`**: If you add, remove, or rename a command file, update `.forge/update-manifest.yaml` to classify it in `framework.paths`, `removed.paths`, or `obsolete.mappings` as appropriate.

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

## Contributing from a Consumer Project

If you're using FORGE in your project (not developing FORGE itself), your upstream contribution path depends on where your project's template comes from. Check `_src_path` in your `.copier-answers.yml`:

### Path A — Canonical FORGE (`Renozoic-Foundry/forge-public`)

Your `_src_path` contains `Renozoic-Foundry/forge-public`. Contribute directly:

1. Open an issue or PR on [Renozoic-Foundry/forge-public](https://github.com/Renozoic-Foundry/forge-public)
2. Include the signal entry (SIG-NNN) or insight (CI-NNN) that prompted the improvement
3. Ensure the change is domain-neutral — no project-specific names, paths, or config
4. Apply the change to the **canonical source** (repo-root `.forge/commands/`, `.forge/bin`, `.forge/lib`, or root docs) — the plugin payload (`.claude/`) and `template/` tree are generated downstream surfaces; regenerate them with `bash .forge/bin/forge-parity.sh` rather than editing copies

### Path B — Private Fork (org-specific URL)

Your `_src_path` points to an internal repo (e.g., `dev.azure.com/yourorg/...`). Contribute to your fork maintainer first:

1. Open an issue or PR on your **fork's repo** (not Renozoic-Foundry)
2. Your fork maintainer decides whether to upstream the improvement
3. If the improvement is domain-neutral and benefits all FORGE users, the fork maintainer can open a PR on [Renozoic-Foundry/forge-public](https://github.com/Renozoic-Foundry/forge-public)

This two-hop path (consumer → fork → upstream) ensures org-specific changes don't leak upstream, while genuinely universal improvements still reach the canonical repo.

### Path C — Local Path (FORGE developer)

Your `_src_path` is a local filesystem path. You're working directly on FORGE — use the standard development workflow above.

## Contribution Checklist

Before submitting any upstream contribution:

- [ ] Change is **domain-neutral** — no project-specific names, paths, or commands
- [ ] All template files retain `# Framework: FORGE` header
- [ ] `<!-- customize -->` markers are used at project-specific extension points
- [ ] Copier variables (e.g. `{{ project_name }}`) are used where appropriate in `.jinja` files
- [ ] Change has been tested via `copier copy` (see Testing section)
- [ ] PR description includes provenance (which signal/error/insight prompted this)
- [ ] Shellcheck passes on any modified `.sh` files

## Response Times

FORGE is maintained by a small team. Here's what to expect:

| Type | Target Response | Notes |
|------|----------------|-------|
| **Security vulnerability** | 48 hours | Use GitHub **private vulnerability reporting** — see [SECURITY.md](SECURITY.md) |
| **Bug report** | 3-5 business days | Faster if reproduction steps are included |
| **Feature request** | 1-2 weeks | Evaluated against the backlog during evolve loop reviews |
| **Pull request** | 1-2 weeks | Faster for small changes with clear spec references |
| **Question / discussion** | 3-5 business days | |

These are targets, not guarantees. If something is urgent, note it in the issue title.

## Pull Request Review

When reviewing PRs, maintainers check:

- **Spec alignment**: Does the PR reference a spec? Changes without specs need one created first.
- **Template integrity**: Do template files render correctly? (`copier copy . /tmp/test --defaults`)
- **Own-copy sync**: If template commands changed, are the own-copies updated too?
- **Shellcheck**: All `.sh` files pass `scripts/validate-bash.sh`
- **Domain neutrality**: No project-specific names, paths, or internal references

PRs that include a spec reference and pass the contribution checklist above are reviewed fastest.

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Be constructive — every contribution should make the framework better for all users.

## License

By contributing to FORGE, you agree that your contributions will be licensed under the MIT License.
