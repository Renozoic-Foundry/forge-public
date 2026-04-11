# Dev Container Setup

FORGE requires **read-write filesystem access** to the project workspace. This directory contains the devcontainer configuration that ensures correct access in VS Code Dev Containers, GitHub Codespaces, and Docker Compose environments.

If you see `GATE [write-access]: FAIL` from `/forge init`, this README explains how to fix it.

---

## Quick check

Open a terminal in your workspace and run:

```bash
touch .forge/.write-check && rm .forge/.write-check && echo "✅ writable" || echo "❌ read-only"
```

---

## VS Code Dev Containers

The `devcontainer.json` in this directory is pre-configured with:

```json
"workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
```

This bind-mounts your local project folder into the container with read-write access. No additional configuration is needed — open the project in VS Code and choose **"Reopen in Container"**.

**If still read-only after reopening:**
1. Check Docker Desktop → Settings → Resources → File Sharing — ensure your project drive is listed.
2. On Windows: ensure the drive is shared with Docker (`C:\` or wherever the project lives).
3. Rebuild the container: `Dev Containers: Rebuild Container` from the VS Code command palette.

---

## GitHub Codespaces

Codespaces mounts the workspace read-write by default. If you encounter read-only errors:

1. Check that you have **write access** to the repository (not just read access via a fork).
2. Verify you're not in a restricted org policy that makes the Codespace read-only.
3. Try: **Codespaces: Rebuild Container** from the VS Code command palette.

---

## Docker Compose

If you run FORGE in a Docker Compose service, ensure the workspace volume is a **bind mount** (not a named volume), and that it is not marked `read_only`:

```yaml
# ✅ Correct — bind mount, read-write
services:
  dev:
    image: mcr.microsoft.com/devcontainers/python:3.11
    volumes:
      - .:/workspace:cached   # bind mount, no read_only flag
    working_dir: /workspace

# ❌ Wrong — read_only will break FORGE
services:
  dev:
    volumes:
      - .:/workspace:ro       # ro = read-only, FORGE cannot write
```

---

## Local development (no container)

If you're developing locally without a container, write access depends on your OS file permissions. Ensure:
- The project directory is owned by your user (`ls -la` → owner matches `whoami`)
- No immutable flag set (`chattr -i <dir>` on Linux if needed)
- On Windows: not in a OneDrive "Files On-Demand" folder that hasn't synced

---

## Delegated-write fallback

If you genuinely cannot get read-write access in your environment (e.g. a locked-down CI sandbox), use the **delegated-write protocol**: the agent emits a structured write-request message via NanoClaw, and another agent or human applies the changes.

See: `.forge/templates/delegated-write-protocol.md`
