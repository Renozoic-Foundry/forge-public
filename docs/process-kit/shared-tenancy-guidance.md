# Shared-Tenancy Guidance for `/forge stoke`

Operator guidance for running `/forge stoke` on systems where `/tmp` is shared with other users or tenants.

## Who this applies to

This guidance is relevant when:

- You run `/forge stoke` inside a **CI runner** that reuses `/tmp` across jobs or users (e.g., GitHub Actions shared-tmp runners, shared Jenkins agents, multi-tenant GitLab runners).
- You run `/forge stoke` on a **multi-user server or shared dev box** where `/tmp` is world-writable and other users have active sessions.
- You run `/forge stoke` inside a **container that inherits a shared host `/tmp`** via bind mount.

## Who this does NOT apply to

No action needed in any of these environments:

- **Single-user workstation** (your personal laptop or desktop). This is FORGE's baseline threat model and the default for almost all operators.
- **macOS default** — the per-user `$TMPDIR` (under `/var/folders/<hash>/`) is already scoped to the logged-in user.
- **Windows single-user Git Bash** — MSYS2's `/tmp` maps to `$TEMP` which is typically `%LOCALAPPDATA%\Temp`, a per-user path.
- **Containers with an ephemeral per-job `/tmp`** (most modern CI platforms — GitHub Actions default runners, GitLab shared runners with per-job tmpfs, CircleCI's default config). The container's `/tmp` is destroyed at job end and is not observable by other jobs.

If you're not sure: assume FORGE's baseline (single-operator-per-workstation) unless you have explicit evidence the environment is multi-tenant.

## The risk

`/forge stoke`'s Step 0b creates a temporary directory `$FORGE_TMP` = `${TMPDIR:-${TEMP:-/tmp}}/forge-manifest-check` and renders the upstream template into it. On a shared `/tmp` filesystem, a co-tenant process could theoretically observe the directory's contents or interfere with file creation during the brief window between directory creation (`mkdir`) and permission tightening (`chmod 700`). The window is small (microseconds to milliseconds depending on process scheduling), but on multi-tenant CI runners, it's realistic.

The risk is narrow: FORGE's rendered template does not contain secrets, but it may contain project-specific configuration that a co-tenant should not observe.

## The mitigation

Set `TMPDIR` to a per-user path before invoking `/forge stoke`. This moves the entire temp directory lifecycle out of the shared filesystem — the attack surface disappears regardless of the creation primitive used.

### GitHub Actions (shared-tmp runner)

```yaml
- name: Stoke FORGE
  run: |
    export TMPDIR="$RUNNER_TEMP/forge"
    mkdir -p "$TMPDIR"
    /forge stoke
```

`$RUNNER_TEMP` is per-job and cleaned up by GitHub after the job completes. If the runner is self-hosted and shared, this still isolates the current job from co-tenant jobs.

### Generic Unix multi-user dev box

```bash
export TMPDIR="$HOME/.cache/forge"
mkdir -p "$TMPDIR"
chmod 700 "$TMPDIR"
/forge stoke
```

`$HOME` is owner-only on a properly-configured Unix system, so no co-tenant on the same box can read the rendered content.

### CI container with no XDG_RUNTIME_DIR

```bash
# Fallback when XDG_RUNTIME_DIR is unset (common in containers)
export TMPDIR="${XDG_RUNTIME_DIR:-$HOME/.cache/forge}"
mkdir -p "$TMPDIR"
/forge stoke
```

This expression prefers `$XDG_RUNTIME_DIR` (which is always per-user on systems that set it — typically `/run/user/<uid>`) and falls back to a per-user cache path if unset.

## Why not change the code instead?

Prior research ([docs/research/explore-299-tmpdir-hardening.md](../research/explore-299-tmpdir-hardening.md)) evaluated replacing Step 0b's `mkdir -p && chmod 700` with the atomic `install -d -m 700` primitive. The primitive fails on Git Bash (Windows 11 MSYS2/NTFS permission emulation does not honor the mode bits), and the required fallback restores the TOCTOU window the change was meant to close. Operator guidance is a complete mitigation without introducing cross-platform fragility.

If you encounter a situation where operator guidance is insufficient — a real shared-tenancy incident, or a Lane B compliance profile that declares shared tenancy as in-scope — Spec 299 carries re-activation triggers to revisit code-side atomic-perms work with a proper portability matrix (including macOS BSD `install` testing).

## References

- [docs/specs/299-forge-stoke-tmpdir-hardening.md](../specs/299-forge-stoke-tmpdir-hardening.md) — the governing spec
- [docs/specs/296-forge-stoke-honor-answers-in-step-0b.md](../specs/296-forge-stoke-honor-answers-in-step-0b.md) — the hotfix that established the current temp-dir pattern
- [docs/research/explore-299-tmpdir-hardening.md](../research/explore-299-tmpdir-hardening.md) — pre-spec research including the Git Bash portability test
- FORGE's baseline threat model: single-operator-per-workstation. Shared tenancy is a narrow edge case addressed by this guidance, not a redefinition of the baseline.
