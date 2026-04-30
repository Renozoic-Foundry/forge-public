---
name: dependency-audit
description: "Scan for dependency changes and produce a structured risk report"
workflow_stage: review
---

# Framework: FORGE
# Model-Tier: sonnet
Audit dependency manifest changes against a baseline. Usage: /dependency-audit [baseline-ref]

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /dependency-audit — Scan dependency manifests for added, removed, or version-changed packages.
  Usage: /dependency-audit [baseline-ref]
  Arguments:
    baseline-ref — git ref to diff against (default: HEAD~1; use a branch name or commit SHA)
  Behavior:
    - Detects changes in: package.json, requirements.txt, pyproject.toml, Cargo.toml, go.mod, Gemfile, pom.xml, build.gradle
    - Reports each dependency change with risk flags: new-dependency, major-version-bump, removed, minor-bump, patch-bump
    - Outputs a structured table for review
    - Does NOT run vulnerability scanners (use npm audit / pip-audit / cargo audit separately)
  See: docs/process-kit/dependency-vetting-checklist.md
  ```
  Stop — do not execute any further steps.

---

## Step 1 — Resolve baseline

Determine the baseline git ref:
- If $ARGUMENTS provides a ref (commit SHA, branch name, tag): use that.
- If no argument: use `HEAD~1` as default.
- If the repo has no commits or the ref is invalid: report "No valid baseline ref. Provide a commit SHA or branch name." Stop.

Verify the ref exists:
```bash
git rev-parse --verify <baseline-ref> 2>/dev/null
```
If invalid: "Baseline ref '<ref>' not found. Provide a valid commit SHA, branch, or tag." Stop.

## Step 2 — Detect manifest files

Scan the working tree for known dependency manifest files. Supported manifests:

| Ecosystem | Manifest file(s) |
|-----------|-------------------|
| Node.js | `package.json` |
| Python (pip) | `requirements.txt`, `requirements/*.txt` |
| Python (Poetry/PEP 621) | `pyproject.toml` |
| Rust | `Cargo.toml` |
| Go | `go.mod` |
| Ruby | `Gemfile` |
| Java (Maven) | `pom.xml` |
| Java (Gradle) | `build.gradle`, `build.gradle.kts` |

Find all manifest files that have changes between the baseline and working tree:
```bash
git diff <baseline-ref> --name-only | grep -E "(package\.json|requirements.*\.txt|pyproject\.toml|Cargo\.toml|go\.mod|Gemfile|pom\.xml|build\.gradle(\.kts)?)"
```

If no manifest files changed: report "No dependency manifest changes detected between <baseline-ref> and working tree." Stop.

## Step 3 — Parse dependency changes

For each changed manifest file, compare the baseline version to the current version and extract dependency changes.

**Parsing strategy per ecosystem:**

- **package.json**: Compare `dependencies`, `devDependencies`, `peerDependencies`, and `optionalDependencies` objects. Extract package name and version range.
- **requirements.txt**: Compare lines matching `package==version` or `package>=version` patterns. Ignore comments and blank lines.
- **pyproject.toml**: Compare `[project.dependencies]`, `[project.optional-dependencies.*]`, and `[tool.poetry.dependencies]` sections.
- **Cargo.toml**: Compare `[dependencies]`, `[dev-dependencies]`, and `[build-dependencies]` sections.
- **go.mod**: Compare `require` block entries (`module v<version>`).
- **Gemfile**: Compare `gem 'name', 'version'` entries.
- **pom.xml**: Compare `<dependency>` blocks for `<groupId>:<artifactId>` and `<version>`.
- **build.gradle**: Compare `implementation`, `api`, `testImplementation`, `compileOnly` dependency declarations.

For the baseline version, retrieve the file content at the baseline ref:
```bash
git show <baseline-ref>:<manifest-path>
```

## Step 4 — Classify risk

For each dependency change, assign a risk flag:

| Change type | Risk flag | Description |
|------------|-----------|-------------|
| New dependency (not in baseline) | `new-dependency` | Highest risk — new supply chain surface |
| Dependency removed | `removed` | Review — may indicate feature removal or replacement |
| Major version bump (e.g., 2.x → 3.x) | `major-version-bump` | High risk — potential breaking changes |
| Minor version bump | `minor-bump` | Low risk |
| Patch version bump | `patch-bump` | Minimal risk |

## Step 5 — Produce report

Output a structured report:

```
## Dependency Audit Report
Baseline: <baseline-ref> (<short SHA>)
Current: working tree
Date: YYYY-MM-DD

### Summary
- Manifests changed: <count>
- Dependencies added: <count>
- Dependencies removed: <count>
- Version changes: <count>
- Risk flags: <count> new-dependency, <count> major-version-bump, <count> removed

### Changes

| Ecosystem | Manifest | Package | Old Version | New Version | Risk Flag |
|-----------|----------|---------|-------------|-------------|-----------|
| Node.js | package.json | lodash | — | 4.17.21 | new-dependency |
| Python | requirements.txt | requests | 2.28.0 | 2.31.0 | minor-bump |
| ... | ... | ... | ... | ... | ... |

### Recommendations
<automated — see active detection below>
```

### [mechanical] Dependency Risk Active Detection (Spec 180)

After generating the report, scan the Changes table for risk flags and present targeted prompts:

**New dependency detection**: If any row has Risk Flag = `new-dependency`:
  Present:
  ```
  NEW DEPENDENCIES DETECTED — The following packages were added:
  <list of new-dependency entries with ecosystem and package name>

  New dependencies increase supply chain risk and attack surface.
  ```
  > **Choose** — type a number or keyword:
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `vet` | Review each against the dependency-vetting checklist (docs/process-kit/dependency-vetting-checklist.md) |
  > | **2** | `skip` | Proceed — vetting deferred to close gate |

  - If `vet`: for each new dependency, walk through the vetting checklist (maintenance activity, license, size, alternatives considered). Record results in the report.
  - If `skip`: append note: "New dependency vetting deferred."

**Major version bump detection**: If any row has Risk Flag = `major-version-bump`:
  Present:
  ```
  MAJOR VERSION BUMPS DETECTED — The following packages have major version changes:
  <list of major-version-bump entries>

  Major version bumps may include breaking API changes.
  ```
  > **Choose** — type a number or keyword:
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `review` | Check each for breaking changes now |
  > | **2** | `skip` | Proceed — breaking change review deferred |

  - If `review`: for each major bump, check the changelog/migration guide for breaking changes. Record findings.
  - If `skip`: append note: "Major version bump review deferred."

**Removed dependency detection**: If any row has Risk Flag = `removed`:
  Present:
  ```
  DEPENDENCIES REMOVED — The following packages were removed:
  <list of removed entries>

  Confirm these removals are intentional and no code still references them.
  ```
  > **Choose** — type a number or keyword:
  > | # | Action | What happens |
  > |---|--------|--------------|
  > | **1** | `confirm` | Verify no remaining references and confirm removal |
  > | **2** | `skip` | Proceed — removal verification deferred |

  - If `confirm`: run `grep -r "<package-name>" --include="*.{js,ts,py,go,rs}" .` for each removed package. Report any remaining references.
  - If `skip`: append note: "Removed dependency verification deferred."

**Ecosystem audit tools**: After risk-flag prompts, automatically detect which ecosystems are present and suggest the appropriate audit command:
- If `package.json` changed: suggest `npm audit` or `yarn audit`
- If `requirements*.txt` or `pyproject.toml` changed: suggest `pip-audit`
- If `Cargo.toml` changed: suggest `cargo audit`
- If `go.mod` changed: suggest `govulncheck`
- If `Gemfile` changed: suggest `bundle audit`

If **no risk flags found** (all changes are `minor-bump` or `patch-bump`): report "All dependency changes are low-risk version bumps. No action needed." Proceed silently.

## Step 6 — Record in spec evidence (if spec context available)

If this command is running in the context of a spec (e.g., called from `/implement`), append the dependency list to the spec's `## Evidence` section:

```
### Dependency Changes (Spec 126)
<paste the Changes table from the report>
Signal: DEPENDENCY_REVIEW_REQUIRED (if any new-dependency or major-version-bump flags present)
```

If no `new-dependency` or `major-version-bump` flags are present, do not emit the `DEPENDENCY_REVIEW_REQUIRED` signal.
