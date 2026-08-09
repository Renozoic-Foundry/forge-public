---
name: test
description: "Run the test suite and report results"
disable-model-invocation: false
---
# Framework: FORGE
Run the project's test suite and report results. Accepts an optional path to a specific test file
or directory, or an explicit command override.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /test — Run the project test suite.
  Usage: /test [path/to/tests] [--cmd "<command>"]
  Arguments:
    path (optional)   — run only that file or directory. Omit to run everything.
    --cmd "<command>" — run this exact command instead of the resolved one.
  Examples:
    /test                            — run the full suite with the resolved command
    /test tests/unit                 — run one path
    /test --cmd "npm run test:ci"    — override the resolved command for this run
  Behavior: Resolves the project's test command (explicit override → configured value →
  detected stack → ask), prints it, runs it, then reports pass/fail and identifies new
  vs pre-existing failures.
  See: CLAUDE.md (key commands)
  ```
  Stop — do not execute any further steps.

---

Usage: /test [optional: path] [--cmd "<command>"]

## [mechanical] Step 1 — Resolve the test command (Spec 651)

FORGE does not assume a stack. The command is resolved in a fixed precedence order and the
source is always reported, so an operator can see *why* a given command ran. Run the resolver
below with `FORGE_TEST_CMD_ARG` set to the `--cmd` value when one was passed (unset otherwise):

```bash
# forge:spec-651-resolve-block:start
# Precedence: explicit --cmd  ->  project.test_command in .forge/onboarding.yaml
#             ->  file-presence stack detection  ->  unresolved (Step 2 asks).
# This block RESOLVES and PRINTS only. It never executes the command — the
# operator sees the resolved string first (Spec 651 Constraints).
forge_test_cmd=""
forge_test_src=""

if [[ -n "${FORGE_TEST_CMD_ARG:-}" ]]; then
  forge_test_cmd="$FORGE_TEST_CMD_ARG"
  forge_test_src="explicit --cmd argument"
fi

if [[ -z "$forge_test_cmd" && -f .forge/onboarding.yaml ]]; then
  configured="$(sed -n 's/^[[:space:]]*test_command:[[:space:]]*//p' .forge/onboarding.yaml | head -1)"
  configured="${configured%\"}"; configured="${configured#\"}"
  configured="${configured%\'}"; configured="${configured#\'}"
  if [[ -n "$configured" && "$configured" != "null" && "$configured" != "~" ]]; then
    forge_test_cmd="$configured"
    forge_test_src="project.test_command (.forge/onboarding.yaml)"
  fi
fi

# File-presence detection only — no dependency-detection framework (Constraints).
# Order is fixed and declared so a polyglot repo resolves predictably.
if [[ -z "$forge_test_cmd" ]]; then
  if [[ -f package.json ]]; then
    forge_test_cmd="npm test";        forge_test_src="detected stack: Node (package.json)"
  elif [[ -f pyproject.toml || -f setup.py ]]; then
    forge_test_cmd="pytest -q";       forge_test_src="detected stack: Python (pyproject.toml/setup.py)"
  elif [[ -f go.mod ]]; then
    forge_test_cmd="go test ./...";   forge_test_src="detected stack: Go (go.mod)"
  elif [[ -f Cargo.toml ]]; then
    forge_test_cmd="cargo test";      forge_test_src="detected stack: Rust (Cargo.toml)"
  elif compgen -G "*.csproj" > /dev/null 2>&1 || compgen -G "*.sln" > /dev/null 2>&1; then
    forge_test_cmd="dotnet test";     forge_test_src="detected stack: .NET (*.csproj/*.sln)"
  fi
fi

if [[ -z "$forge_test_cmd" ]]; then
  echo "Test command: (unresolved)"
  echo "Resolved from: none — no configured command and no recognized stack"
else
  echo "Test command: $forge_test_cmd"
  echo "Resolved from: $forge_test_src"
fi
# forge:spec-651-resolve-block:end
```

**PowerShell / Windows equivalent** (same precedence; command quoting differs):
```powershell
$forgeTestCmd = ''
$forgeTestSrc = ''
if ($env:FORGE_TEST_CMD_ARG) { $forgeTestCmd = $env:FORGE_TEST_CMD_ARG; $forgeTestSrc = 'explicit --cmd argument' }
if (-not $forgeTestCmd -and (Test-Path '.forge/onboarding.yaml')) {
  $line = Select-String -Path '.forge/onboarding.yaml' -Pattern '^\s*test_command:\s*(.*)$' |
    Select-Object -First 1
  if ($line) {
    $configured = $line.Matches[0].Groups[1].Value.Trim().Trim('"').Trim("'")
    if ($configured -and $configured -ne 'null' -and $configured -ne '~') {
      $forgeTestCmd = $configured; $forgeTestSrc = 'project.test_command (.forge/onboarding.yaml)'
    }
  }
}
if (-not $forgeTestCmd) {
  if     (Test-Path 'package.json')   { $forgeTestCmd = 'npm test';      $forgeTestSrc = 'detected stack: Node (package.json)' }
  elseif ((Test-Path 'pyproject.toml') -or (Test-Path 'setup.py')) { $forgeTestCmd = 'pytest -q'; $forgeTestSrc = 'detected stack: Python (pyproject.toml/setup.py)' }
  elseif (Test-Path 'go.mod')         { $forgeTestCmd = 'go test ./...'; $forgeTestSrc = 'detected stack: Go (go.mod)' }
  elseif (Test-Path 'Cargo.toml')     { $forgeTestCmd = 'cargo test';    $forgeTestSrc = 'detected stack: Rust (Cargo.toml)' }
  elseif ((Get-ChildItem -Filter *.csproj -ErrorAction SilentlyContinue) -or
          (Get-ChildItem -Filter *.sln    -ErrorAction SilentlyContinue)) { $forgeTestCmd = 'dotnet test'; $forgeTestSrc = 'detected stack: .NET (*.csproj/*.sln)' }
}
if (-not $forgeTestCmd) {
  "Test command: (unresolved)"
  "Resolved from: none — no configured command and no recognized stack"
} else {
  "Test command: $forgeTestCmd"
  "Resolved from: $forgeTestSrc"
}
```

## [decision] Step 2 — Ask, only when nothing resolved

If Step 1 printed `(unresolved)`, ask exactly ONE question — never fall back to a stack-specific
runner, and never fail with that runner's error:

```
No test command is configured and no stack was detected.
What should /test run? (a command, or `none` to skip testing this run)
```

**STOP — wait for response.** On a command: use it for this run and offer to persist it with
`/configure` → Test command. On `none`: report `No test command configured — skipping.` and stop.

## [mechanical] Step 3 — Run

1. Echo the resolved command and its source (Step 1's two lines) before running anything.
2. If a path argument was provided, append it to the resolved command; otherwise run it as-is.
3. Run in the project root.

## [mechanical] Step 4 — Report

- Pass/fail count
- Any failures, with the runner's short output
- Whether the result matches the expectation from the spec being worked on

If any tests fail:
- Identify whether the failure is in new code (this session) or pre-existing
- If new: attempt to fix before proceeding
- If pre-existing: note it as a known defect in the session log and continue

## [mechanical] Lint command

The delivery gate's lint step resolves `project.lint_command` from `.forge/onboarding.yaml` by the
same precedence and reports the same way. Stack defaults, when nothing is configured: Node →
`eslint .`, Python → `ruff check .`, Go → `golangci-lint run`, Rust → `cargo clippy`, .NET →
`dotnet format --verify-no-changes`. With nothing configured and no stack detected, lint is
skipped with a stated reason — never silently, and never with an assumed runner.
