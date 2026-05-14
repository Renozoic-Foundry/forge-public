# Cross-Platform Python Invocation Guide (Spec 401)

FORGE runs on Windows, macOS, and Linux. Python interpreter resolution differs across these platforms in ways that broke FORGE's pre-Spec-401 conventions:

- The python.org Windows installer ships only `python.exe` and `py.exe` — no `python3.exe`. Hardcoded `python3 ...` invocations fail on bare Windows.
- macOS Homebrew, pyenv, system-Python, and venv each expose different combinations of `python` / `python3`.
- The Microsoft Store ships zero-byte `python.exe` aliases that launch the Store rather than a working interpreter.

Spec 401 ships a single primitive that resolves these differences cleanly: the `forge-py` wrapper.

## Wrapper convention

**Always invoke FORGE-shipped Python helpers via the wrapper:**

```bash
.forge/bin/forge-py <script-path> [args...]
```

This invocation string is byte-identical across platforms and mirrors. The wrapper is provided in two parity copies:

- `.forge/bin/forge-py` — POSIX shim (`/bin/sh`, executable bit set)
- `.forge/bin/forge-py.cmd` — Windows batch shim

### Resolution chain

The wrapper iterates candidates in order, accepting the first that meets the floor:

1. `python3` (POSIX-canonical; absent on bare Windows)
2. `python` (Windows + macOS + many Linux distros)
3. `py -3` (Windows py-launcher; ships with python.org installer)

On each candidate found on PATH, the wrapper runs `--version` and parses major.minor. If the version is below the floor (currently **Python 3.10**), it **falls through** to the next candidate rather than failing immediately. This handles the Microsoft Store stub + py-launcher coexistence: an old `python.exe` that's actually the Store stub or below the floor will not block resolution to a working `py -3`.

If no candidate satisfies the floor, the wrapper exits >=1 with a clear stderr error.

### Microsoft Store stub skip (Windows only)

The Windows shim detects paths under `%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe` (the Microsoft Store alias location) and **skips them unconditionally**. The Store stub launches the Store app rather than running a real interpreter, producing confusing "hangs" or download dialogs. The shim treats Store-aliased candidates as not-resolved and falls through.

### Version floor

**Python 3.10+ is the floor.** This was raised from 3.9 in Spec 401, looking forward to features like structural pattern matching and improved typing. Defense-in-depth: each FORGE-shipped helper also carries a module-top guard that exits >=1 with a clear error if invoked under Python <3.10 (catches direct `./script.py` invocations that bypass the wrapper).

## Supported environments matrix

| Environment                          | Resolution      | Notes                                                                                |
|--------------------------------------|-----------------|--------------------------------------------------------------------------------------|
| Windows native (python.org installer)| `py -3`         | `python3` absent; `python` may resolve. Wrapper's fall-through handles this.          |
| Windows VS Code extension            | `py -3` or `python` | Operator's primary environment. Real-Windows validation captured in Spec 401 evidence. |
| Windows + Microsoft Store stub       | `py -3`         | Stub `python.exe` detected and skipped; wrapper falls through to py-launcher.         |
| macOS default (no homebrew)          | `python3`       | `python` is Python 2 on legacy macOS; `python3` is the canonical command.            |
| macOS homebrew                       | `python3`       | Same as default. Brew-installed Python takes precedence.                             |
| macOS pyenv                          | `python3` or `python` | Whichever the active pyenv shim exposes. Both work.                              |
| Linux system Python                  | `python3`       | All major distros expose `python3`; some legacy ones don't expose `python`.          |
| Linux + active venv                  | `python` or `python3` | Inside a venv, both names resolve to the venv's interpreter.                      |
| Devcontainer / Codespaces            | `python3`       | Standard Microsoft devcontainer Python images expose `python3`.                      |

## Windows prerequisite detail

FORGE Copier `_tasks` blocks (Spec 400) and several FORGE shell snippets use `sh -c '...'`. POSIX `sh` is **not** native on Windows — it must come from one of two sources:

### Option 1 — Git for Windows installed with "Use Git and optional Unix tools from the Command Prompt"

1. Re-run the Git for Windows installer (https://gitforwindows.org/).
2. On the "Adjusting your PATH environment" screen, select **option 3 — "Use Git and optional Unix tools from the Command Prompt"**. This places `sh.exe`, `test.exe`, `cat.exe`, etc. on PATH for cmd.exe and PowerShell.
3. Restart your shell. Verify with `where sh`.

### Option 2 — Launch FORGE workflows from a Git Bash terminal

1. Right-click in your project folder → "Git Bash Here" (or open Git Bash from the start menu and `cd` to your project).
2. Run FORGE commands from Git Bash. `sh`, `test`, etc. are native.

### Verifying

```cmd
where sh
```

```bash
command -v sh
```

If either prints a path, you're good. If not, install Git for Windows option 3 or use Git Bash.

## stdlib-only constraint

All FORGE-shipped Python helpers (`assemble_view.py`, `migrate-to-derived-view.py`, `render_backlog.py`, `render_changelog.py`, `render_spec_index.py`, `stoke.py`) MUST use only Python 3.10+ stdlib modules. **One exception**: `strategic-scope.py` imports `yaml` (PyYAML), which is a transitive FORGE dependency via Copier — PyYAML ships in the same install set as Copier, so requiring it adds no new install burden. The stdlib-only audit (`tests/test-spec-401-stdlib-only-audit.py`) whitelists `yaml` for `strategic-scope.py` only.

The constraint exists so FORGE never grows a Python-package install step beyond Copier itself. Any new helper that needs a third-party library must either (a) replace the dependency with stdlib equivalents, or (b) get an explicit spec-driven exception added to the audit whitelist.

## Known issues

### Microsoft Store stub (Windows)

`%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe` is a zero-byte stub that opens the Microsoft Store. Any tool that runs `where python` and uses the first hit can hang or display the Store page. **The wrapper detects and skips this path.** If you see Microsoft Store opening when you run a FORGE command, run `where python` to confirm; the wrapper should already skip it, but verify your `forge-py.cmd` is current (Spec 401+).

### pyenv shim setup

If `pyenv` is installed but `pyenv init` has not been added to your shell rc, the `python` and `python3` shims may not be on PATH. Add `eval "$(pyenv init --path)"` to `~/.bash_profile` or `~/.zshenv`.

### Devcontainer host-vs-container split

When running FORGE commands from a host shell while files live in a devcontainer (or vice-versa), Python resolution differs because each environment has a different PATH. Always run FORGE commands from inside the environment whose Python you intend to use.

## Diagnosis decision tree

**Symptom: FORGE command fails with `python: command not found` or `python3: command not found`**

1. Are you on Windows? → Install python.org Python (3.10+) or use Microsoft Store official Python (NOT the stub alias). Verify: `python --version` or `py -3 --version`.
2. Are you on Linux? → Install via your package manager: `sudo apt install python3.10` (Ubuntu/Debian) or equivalent. Verify: `python3 --version`.
3. Are you on macOS? → Install via Homebrew: `brew install python@3.10`. Verify: `python3 --version`.

**Symptom: FORGE command fails with `error: Python 3.10+ required (found 3.9.X)`**

1. Confirm version: `python3 --version` (POSIX) or `py -0` (Windows; lists installed py-launcher Pythons).
2. Install Python 3.10+ alongside your current version.
3. On POSIX: `python3.10` should now resolve. Update PATH order or alias if needed.
4. On Windows: `py -3.10` should resolve. The wrapper's resolution chain will find it via `py -3`.

**Symptom: FORGE command opens the Microsoft Store on Windows**

1. Run `where python` — if the first hit is under `WindowsApps\`, that's the stub.
2. The wrapper should already skip this path. Verify your `.forge/bin/forge-py.cmd` is current (Spec 401+).
3. If the wrapper still routes to the stub, file a bug: include `where python`, `where py`, and the wrapper's stderr.

**Symptom: FORGE command fails with `Windows: 'sh' not found on PATH`**

See the [Windows prerequisite detail](#windows-prerequisite-detail) section above. Install Git for Windows option 3 or launch from Git Bash.

## See also

- [Spec 401 — Cross-Platform Python Invocation Wrapper](../specs/401-cross-platform-python-wrapper.md)
- [ADR-401 — Python Invocation Wrapper](../decisions/ADR-401-python-invocation-wrapper.md)
- [docs/research/explore-cross-platform-python-invocation.md](../research/explore-cross-platform-python-invocation.md)
