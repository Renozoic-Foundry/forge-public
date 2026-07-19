# FORGE Scripts

Validation and build scripts for maintaining a FORGE template repository. These scripts operate on the template source (this repo), not on consumer projects bootstrapped from it.

If you are maintaining a private fork of FORGE, these scripts are your QA toolkit.

## Scripts

### Validation

| Script | Purpose | When to run |
|--------|---------|-------------|
| `validate-bash.sh` | Strip Jinja2 tags, then run shellcheck on all template bash scripts | After modifying any `.sh` file in `template/` |
| `../.forge/bin/forge-sync-cross-level.sh` | Propagate canonical repo-root sources to `template/` mirrors (supersedes `validate-command-sync.sh` — Spec 270) | After editing `.forge/commands/`, `.claude/agents/`, or `docs/process-kit/`; `--check` in CI/pre-commit |
| `smoke-test-template.sh` | Run `copier copy --defaults`, verify output renders cleanly (no Jinja2 artifacts, key files present, `.copier-answers.yml` generated) | After any template change |
| `smoke-test-runtime.sh` | Bootstrap a project, then exercise the agent runtime pipeline in `--dry-run` mode | After modifying runtime scripts in `template/.forge/bin/` or `template/.forge/adapters/` |

### Build (generated reference docs — Spec 571)

| Script | Purpose | When to run |
|--------|---------|-------------|
| `gen-command-reference.sh` | Regenerate `docs/command-reference.md` from the canonical command source (`.forge/commands/` + `invocation-policy.yaml`) | After adding or modifying slash commands (`--write` to write in place) |
| `gen-quick-reference.sh` | Regenerate both `docs/QUICK-REFERENCE.md` and `template/docs/QUICK-REFERENCE.md` from the same canonical source | After adding or modifying slash commands (`--write`) |
| `gen-agents-config-reference.py` | Regenerate `docs/agents-config-reference.md` — defaults read live from `AGENTS.md`, descriptions from `scripts/lib/agents-config-reference-content.yaml` | After changing an AGENTS.md config block (run via `.forge/bin/forge-py`, `--write`) |
| `compose-modules.sh` | Assemble command files from core + enabled modules based on `onboarding.yaml` | Used by `/onboarding`; run manually with `--check` to inspect module status |

Generated docs carry a provenance header (source content hash + plugin version) and a
revision-history section; `bash .forge/bin/forge-parity.sh --check` (Surface 7) fails when a
committed generated doc is stale relative to its canonical sources.

### Internal (not distributed to forge-public)

| Script | Purpose |
|--------|---------|
| `sync-to-public.sh` | Sync the public subset of this repo to forge-public |
| `validate-spec-index.sh` | Validate `docs/specs/README.md` consistency |
| `validate-readme-stats.sh` | Validate README stats against spec count |
| `validate-public-docs.sh` | Validate public-facing docs (links, deprecated refs) |

## Usage

All scripts are executable and run from the repo root:

```bash
# Validate all bash scripts
bash scripts/validate-bash.sh

# Validate with verbose output
bash scripts/validate-bash.sh --verbose

# Full generated-surface parity check (mirrors, plugin payload, skills, generated docs)
bash .forge/bin/forge-parity.sh --check

# Full template smoke test (legacy Copier scaffold path)
bash scripts/smoke-test-template.sh

# Runtime smoke test
bash scripts/smoke-test-runtime.sh

# Regenerate the reference docs after command/config changes
bash scripts/gen-command-reference.sh --write
bash scripts/gen-quick-reference.sh --write
.forge/bin/forge-py scripts/gen-agents-config-reference.py --write

# Check module status without modifying files
bash scripts/compose-modules.sh --check
```

## For fork maintainers

If you are maintaining a private fork of this repository:

1. **After modifying framework files**, run the validation suite:
   ```bash
   bash scripts/validate-bash.sh
   bash .forge/bin/forge-parity.sh --check
   bash scripts/smoke-test-template.sh
   ```

2. **After adding new commands**, regenerate the reference docs:
   ```bash
   bash scripts/gen-command-reference.sh --write
   bash scripts/gen-quick-reference.sh --write
   ```

3. **CI integration**: These scripts exit non-zero on failure, making them suitable for CI pipelines. A minimal GitHub Actions workflow:
   ```yaml
   - run: bash scripts/validate-bash.sh
   - run: bash .forge/bin/forge-sync-cross-level.sh --check
   - run: bash scripts/smoke-test-template.sh
   ```

## Scripts NOT included in forge-public

The upstream FORGE development repository uses additional internal scripts that are not distributed:

- `sync-to-public.sh` — Syncs the private development repo to the public repo. Fork maintainers who need a similar workflow should write their own.
- `validate-spec-index.sh` — Validates spec index files (development-only artifact).
- `validate-readme-stats.sh` — Validates README statistics against spec counts (development-only artifact).
- `validate-public-docs.sh` — Validates public-facing docs for broken links and deprecated references.
