# Spec Authoring Guide

## Purpose

Conventions for authoring FORGE specs that interact correctly with the spec-vs-HEAD assertion gate (`/implement` Step 0e, Spec 450). The gate diffs spec-asserted state against repo-actual state before implementation begins, so specs must declare their assertions in a machine-checkable form. This guide covers the frontmatter fields the gate reads and the Implementation Summary conventions it parses.

See also: `docs/process-kit/command-authoring-guide.md` (command bodies), `docs/specs/_template.md` (spec skeleton).

## Frontmatter Fields

### `Enforcement-Layers:` (optional)

Declares that the spec touches **multi-layer enforcement** — behavior enforced at two or more distinct code locations that must be audited together (the Spec 437 defect class: a consent gate declared at two layers, each diagnosed in isolation across a 4-hotfix chain).

**Format**: comma-separated list of `<file-path>:<symbol-or-section-name>` entries.

- For **YAML files**, the `:<symbol>` portion is a **key name** (e.g., `_tasks`).
- For **Python files**, it is a **function or class name** (e.g., `main`).
- Empty or absent = "no multi-layer enforcement asserted" — the gate's Check 1 skips silently.

**Worked example** (Spec 437's two layers):

```
- Enforcement-Layers: copier.yml:_tasks, scripts/copier-hooks/forge_consent_gate.py:main
```

This asserts the consent gate is enforced at (1) the Copier task-registration layer — the `_tasks:` key in `copier.yml` — and (2) the hook script itself — `main()` in `forge_consent_gate.py`. At `/implement` Step 0e, both files must exist at HEAD and each symbol must be found in its file, or the gate FAILs with a GAP-LAYER advisory.

**Symbol grammar (injection guard)**: each symbol MUST match `^[A-Za-z_][A-Za-z0-9_. -]{0,127}$`. Symbols failing the grammar are reported as GAP-LAYER (malformed) and are never interpolated into any shell command. Matching uses fixed-string search (`grep -nF`) — never regex interpolation of spec-derived content.

**Limitation — choose unique symbols**: fixed-string matching cannot distinguish a live symbol from a comment or prose mention. A generic symbol like `validator` matches dozens of comment lines and provides false assurance. Choose symbols unique enough that a match is meaningful — prefer definition-site spellings such as a YAML key name (`_tasks`) or a Python function name (`main` is acceptable only because the file is small; prefer more specific names in larger files).

**When to declare layers**: declare when the spec's correctness depends on N≥2 locations staying in sync (gate + validator, script + registration, command body + hook). Do not declare single-location changes — the Implementation Summary already covers simple file existence.

### `Spec-vs-HEAD-Exempt:` (optional, single-use)

Bypasses the Step 0e gate for ONE `/implement` invocation.

**Format**: `- Spec-vs-HEAD-Exempt: <rationale ≥ 30 characters>`

**Semantics**:
- The rationale must be ≥ 30 characters or the gate FAILs.
- **Single-use**: after the gate honors the exemption (PASS+ADVISORY), Step 0e mechanically removes the line from the frontmatter and appends a `spec-vs-head-exempt-used` event to `docs/sessions/activity-log.jsonl`. The exemption cannot silently persist across invocations.
- **Lane B counter-sign**: when `docs/compliance/profile.yaml` is present AND the spec scores BV≥4 AND R≥3, the rationale must contain a `[reviewed-by: <second-operator-identity>]` token (parity with `Consensus-Exempt`, Spec 395).

Use the exemption for genuine edge cases (e.g., implementing against a deliberately stale baseline). If you find yourself exempting routinely, the spec needs `/revise`, not a bypass.

## Implementation Summary Conventions

The Step 0e gate (Check 2) parses the `Changed files:` bullet block under `## Implementation Summary`. Each list-item line is a path entry.

### The `(new)` annotation

Files the spec will **create** must be annotated `(new)`:

```
- Changed files:
  - `.claude/commands/foo.md` (Step 3 extension)
  - `docs/process-kit/foo-guide.md` (new)
  - `.forge/tests/test_spec_NNN_*.py` (new) (3 fixture files)
```

- **Unannotated paths** must exist at HEAD or the gate FAILs with a GAP-SURFACE advisory.
- **`(new)` paths** skip the existence check — they legitimately don't exist yet.
- **Glob entries** (`dir/test_prefix_*.py`): unannotated globs must match ≥1 file at HEAD; globs marked `(new)` are skipped.

`(new)` is a **declaration of intent, not a bypass mechanism**. Marking an existing file `(new)` to evade the existence check is a process violation — the annotation tells reviewers and the gate that creation is part of the spec's scope.

### Append-only side-effect files

Files the implementation appends to as a side effect (e.g., `docs/sessions/activity-log.jsonl`) are conventionally NOT listed in `Changed files:` — the list names surfaces the spec changes deliberately, not logs it touches in passing.

## Step References in Spec Bodies

Step 0e (Check 3) scans spec bodies for command-step references matching `(?<![\w/])/[a-z-]+\s+Step\s+[0-9]+[a-zA-Z+]*` (e.g., `/close Step 2d++++`) and verifies the referenced command file contains a matching step. This check is WARN-only (non-blocking). The `## Revision Log` and `## Evidence` sections are excluded — historical references there are not liveness assertions. When writing the active sections of a spec, reference only steps that exist at HEAD; if a referenced step is renamed or removed later, the WARN tells the next implementer the spec is stale.

## Test Plan Conventions

When a Test Plan mocks framework internals (`_copier_*`, `_copier_conf.*`, `_tasks:` dispatch machinery), it MUST also include at least one integration-level test exercising the real framework code path — see [unit-test-vs-integration-test.md](unit-test-vs-integration-test.md) for the anti-pattern (green unit tests + broken production), worked examples, and the decision tree. (Spec 451)
