# Windows Portability Guide (Spec 482)

FORGE is developed on a Windows-primary host (Git Bash + PowerShell) and must also run
on macOS/Linux. Between 2026-06-12 and 2026-06-15 six distinct Windows/platform
breakages surfaced in a single review window, each hot-fixed in isolation. This guide
consolidates the recurring **classes** behind those incidents into documented host
requirements and four invariants, so the same classes stop recurring.

Reference platforms are macOS and Linux; this guide hardens the **Windows gap**. It is
the companion to [`cross-platform-python-guide.md`](cross-platform-python-guide.md)
(Spec 401, Python interpreter resolution).

Last verified: 2026-06-15

## Pre-flight

Run the advisory pre-flight on any new host before relying on FORGE workflows:

```bash
scripts/check-portability.sh          # Git Bash / macOS / Linux
```
```powershell
pwsh -File scripts/check-portability.ps1   # Windows PowerShell parity
```

It reports `PASS`/`WARN` per host-portability class and **always exits 0** — it is
advisory and never blocks a workflow. A `WARN` names a host condition known to break
FORGE and points back here.

## Host requirements

| Requirement | Why | Pre-flight class |
|-------------|-----|------------------|
| `bash` is **Git Bash / MSYS / Cygwin**, not the WSL launcher | PS1 delegate fixtures and path assumptions break under WSL bash | `bash-flavor` |
| `python` / `python3` / `py` on PATH (3.12+), reachable via `forge-py` | copier entry point + inline helpers need a working interpreter | `python` |
| `sh` on PATH | template MCP runners fail-closed without it | `sh-on-path` |
| `git core.autocrlf` reconciled with `.gitattributes eol=lf` | the cross-level byte-compare must not see phantom CRLF drift | `autocrlf` |
| UTF-8 default encoding (or all repo-file IO via `forge-py`) | bare python inherits cp1252 on Windows and crashes on non-ASCII | `encoding` |

## The four invariant classes

### 1. Encoding — route all repo-file IO through `forge-py`

**Invariant:** *All inline Python that reads or writes repo files goes through the
`forge-py` UTF-8 wrapper — never a bare `python`/`python3`/`py` heredoc or `-c` snippet
that inherits the host's cp1252 default encoding.*

On Windows, `locale.getpreferredencoding()` is typically `cp1252`. A bare
`python3 -c "open('some.md').read()"` then crashes on any non-ASCII byte
(`UnicodeDecodeError`). The `.forge/bin/forge-py` wrapper forces UTF-8 (see the
[cross-platform Python guide](cross-platform-python-guide.md)).

- **Lint:** `scripts/validate-encoding.sh` flags bare-python file IO in
  `.forge/commands/` and `scripts/`. It exempts lines that route through `forge-py`
  and comment/documentation lines.
- **Originating signal:** SIG-474-EA-426 (cp1252 decode crash in ad-hoc inline Python).

### 2. Line endings — normalization-stable cross-level compare

**Invariant:** *The cross-level byte-compare (`forge-sync-cross-level.sh --check`) sees
byte-identical canonical and mirror content regardless of `core.autocrlf`, because
every compared file class is pinned to `eol=lf` in `.gitattributes`.*

With `core.autocrlf=true` (the common Windows default), an unpinned text file
materializes as CRLF in the working tree while its mirror is LF, producing **phantom
drift** in the byte-compare. `.gitattributes` pins `*.md`, `*.sh`, and `.shellcheckrc`
to `eol=lf`; `.ps1` parity scripts are deliberately unpinned (not in the compare set).
See the Spec 482 review note in `.gitattributes` and the
[sync runbook](sync-runbook.md) (Cross-Level Sync section).

- **Originating signal:** SIG-480-CRLF (autocrlf-vs-LF artifact flags phantom drift).

### 3. Interpreter / launcher resolution

**Invariant:** *FORGE never assumes a specific interpreter binary name or that `bash`
is a particular flavor. Python is resolved via the `forge-py` candidate chain
(`python3` → `python` → `py -3`); `bash` is expected to be Git Bash on Windows, not the
WSL launcher.*

Two failure modes collapse into this class:
- The copier entry-point `.exe` silently exited 1 after a Python 3.14 upgrade — the
  resolution chain must tolerate version churn and fall back to the python module
  (`python -m copier`) when the console-script shim breaks.
- PS1 delegate fixtures break when `bash` resolves to the WSL launcher instead of Git
  Bash, because the two resolve paths and line endings differently.

- **Originating signals:** SIG-470-ENV (copier `.exe` broke after Python 3.14),
  SIG-460-A (`bash` → WSL launcher breaks PS1 delegate fixtures).

### 4. Missing-`sh` fail-closed

**Invariant:** *Template runners that shell out degrade gracefully (or document the
`sh`-on-PATH requirement) rather than fail-closed on Windows hosts without `sh`.*

Template MCP runners invoked `sh` directly and fail-closed on bare Windows hosts that
have PowerShell but no `sh` on PATH. The pre-flight surfaces this as a `WARN` so the
operator can put Git Bash's `bin` on PATH before hitting the failure.

- **Originating signals:** SIG-474-A (MCP runners fail-closed without `sh`),
  SIG-451-C (`copier update` old_copy task replay crashes on Windows for recent
  baselines — same interpreter/launcher-resolution family surfacing through copier's
  replay path).

## Signal index

All six originating signals from the 2026-06-12→15 review window:

| Signal | Breakage | Invariant class |
|--------|----------|-----------------|
| SIG-460-A | PS1 delegate fixtures break when `bash` = WSL launcher | 3 (interpreter/launcher) |
| SIG-470-ENV | copier entry-point `.exe` silent exit 1 after Python 3.14 | 3 (interpreter/launcher) |
| SIG-451-C | `copier update` old_copy replay crashes on Windows | 3 (interpreter/launcher) |
| SIG-474-A | template MCP runners fail-closed without `sh` on PATH | 4 (missing-`sh`) |
| SIG-474-EA-426 | cp1252 decode crash in bare inline Python | 1 (encoding) |
| SIG-480-CRLF | autocrlf-vs-LF phantom drift in cross-level compare | 2 (line endings) |

## Verification

- `scripts/check-portability.sh` / `.ps1` — per-class PASS/WARN pre-flight (advisory).
- `scripts/validate-encoding.sh` — encoding-invariant lint (class 1).
- `.forge/bin/tests/test-spec-482-portability.sh` — fixture covering the pre-flight,
  the encoding lint, and CRLF normalization stability.
