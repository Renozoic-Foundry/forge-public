# FORGE Scripts

Validation and build scripts for maintaining a FORGE template repository. These scripts operate on the template source (this repo), not on consumer projects bootstrapped from it.

If you are maintaining a private fork of FORGE, these scripts are your QA toolkit.

## Scripts

### Validation

| Script | Purpose | When to run |
|--------|---------|-------------|
| `validate-bash.sh` | Strip Jinja2 tags, then run shellcheck on all template bash scripts | After modifying any `.sh` file in `template/` |
| `validate-command-sync.sh` | Verify `.claude/commands/` and `.forge/commands/` file parity and content sync | After adding, removing, or renaming a command file |
| `smoke-test-template.sh` | Run `copier copy --defaults`, verify output renders cleanly (no Jinja2 artifacts, key files present, `.copier-answers.yml` generated) | After any template change |
| `smoke-test-runtime.sh` | Bootstrap a project, then exercise the agent runtime pipeline in `--dry-run` mode | After modifying runtime scripts in `template/.forge/bin/` or `template/.forge/adapters/` |

### Build

| Script | Purpose | When to run |
|--------|---------|-------------|
| `gen-command-reference.sh` | Regenerate `docs/command-reference.md` from command source files in `template/.claude/commands/` | After adding or modifying slash commands |
| `compose-modules.sh` | Assemble command files from core + enabled modules based on `onboarding.yaml` | Used by `/onboarding`; run manually with `--check` to inspect module status |

## Usage

All scripts are executable and run from the repo root:

```bash
# Validate all bash scripts
bash scripts/validate-bash.sh

# Validate with verbose output
bash scripts/validate-bash.sh --verbose

# Check command file parity (Phase 1) + content sync (Phase 2)
bash scripts/validate-command-sync.sh --all

# Full template smoke test
bash scripts/smoke-test-template.sh

# Runtime smoke test
bash scripts/smoke-test-runtime.sh

# Regenerate command reference doc
bash scripts/gen-command-reference.sh

# Check module status without modifying files
bash scripts/compose-modules.sh --check
```

## For fork maintainers

If you are maintaining a private fork of this repository:

1. **After modifying template files**, run the validation suite:
   ```bash
   bash scripts/validate-bash.sh
   bash scripts/validate-command-sync.sh --all
   bash scripts/smoke-test-template.sh
   ```

2. **After adding new commands**, also run:
   ```bash
   bash scripts/gen-command-reference.sh
   ```

3. **CI integration**: These scripts exit non-zero on failure, making them suitable for CI pipelines. A minimal GitHub Actions workflow:
   ```yaml
   - run: bash scripts/validate-bash.sh
   - run: bash scripts/validate-command-sync.sh --all
   - run: bash scripts/smoke-test-template.sh
   ```

## Scripts NOT included

The upstream FORGE development repository uses additional internal scripts that are not distributed:

- `sync-to-public.sh` — Syncs the private development repo to this public repo. Fork maintainers who need a similar workflow should write their own.
- `validate-spec-index.sh` — Validates spec index files (development-only artifact).
- `validate-readme-stats.sh` — Validates README statistics against spec counts (development-only artifact).
