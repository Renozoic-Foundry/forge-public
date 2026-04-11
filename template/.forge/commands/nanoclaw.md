---
name: nanoclaw
description: "Manage the NanoClaw container — start, stop, status, logs"
model_tier: sonnet
workflow_stage: configuration
---
# Framework: FORGE
Manage the NanoClaw container — start, stop, status, or view logs.

If $ARGUMENTS is empty, `?`, or `help`:
  Print:
  ```
  /nanoclaw — Manage the NanoClaw gate authentication service.
  Usage: /nanoclaw <start|stop|status|logs [N]>
  Subcommands:
    start   — Start the NanoClaw container, wait for health check, report status
    stop    — Stop the NanoClaw container, confirm shutdown
    status  — Show running state, uptime, port, and health
    logs    — Show last N lines of container logs (default: 50)
  Examples:
    /nanoclaw start
    /nanoclaw status
    /nanoclaw logs 100
  ```
  Stop — do not execute any further steps.

---

**Principle**: All interaction happens in this conversation. Run commands behind the scenes using the Bash tool and present formatted results here. Never ask the user to open a terminal.

---

## Compose file location

Determine the compose file path. Check in order:
1. `docker-compose.nanoclaw.yml` in the project root
2. If not found, report: "No docker-compose.nanoclaw.yml found. Run `/configure-nanoclaw` first or create the compose file."

Set `COMPOSE_FILE` to the resolved path for all subsequent commands.

---

## Subcommand: start

1. Check if the container is already running:
   ```bash
   docker compose -f "$COMPOSE_FILE" ps --format json 2>&1
   ```
   If already running and healthy, report:
   ```
   NanoClaw is already running and healthy.
   Endpoint: http://localhost:8080
   ```
   Ask if the user wants to restart.

2. Load environment from AGENTS.md nanoclaw config. Read the AGENTS.md nanoclaw section and extract values to pass as environment variables:
   ```bash
   NANOCLAW_AUTH_PROVIDER=<from AGENTS.md> \
   NANOCLAW_CHANNEL=<from AGENTS.md> \
   NANOCLAW_SKILL_ID=<from AGENTS.md> \
   NANOCLAW_TIMEOUT=<from AGENTS.md> \
   NANOCLAW_RETRY_COUNT=<from AGENTS.md> \
   NANOCLAW_FALLBACK=<from AGENTS.md> \
   docker compose -f "$COMPOSE_FILE" up -d
   ```

3. Wait for health check (poll up to 30 seconds):
   ```bash
   for i in $(seq 1 6); do
     status=$(docker inspect --format='{{.State.Health.Status}}' nanoclaw 2>/dev/null)
     if [ "$status" = "healthy" ]; then break; fi
     sleep 5
   done
   echo "$status"
   ```

4. Report result:
   - If healthy:
     ```
     ✓ NanoClaw started successfully
       Endpoint: http://localhost:8080
       Health: healthy
       Auth provider: <provider>
       Channel: <channel_id>
     ```
   - If not healthy after 30s:
     ```
     ⚠️ NanoClaw started but health check has not passed yet.
     The container may still be initializing. Run `/nanoclaw status` to check again.
     Run `/nanoclaw logs` to see startup output.
     ```

---

## Subcommand: stop

1. Check if running first:
   ```bash
   docker compose -f "$COMPOSE_FILE" ps --format json 2>&1
   ```
   If not running: "NanoClaw is not running." Stop.

2. Stop the container:
   ```bash
   docker compose -f "$COMPOSE_FILE" down
   ```

3. Report:
   ```
   ✓ NanoClaw stopped.
   ```

---

## Subcommand: status

1. Check container state:
   ```bash
   docker compose -f "$COMPOSE_FILE" ps --format json 2>&1
   ```

2. If running, get detailed info:
   ```bash
   docker inspect --format='{{.State.Status}} | {{.State.StartedAt}} | {{.State.Health.Status}}' nanoclaw 2>/dev/null
   ```

3. Present formatted status:
   - If running:
     ```
     ## NanoClaw Status

     | Field | Value |
     |-------|-------|
     | State | running |
     | Health | healthy |
     | Uptime | 2h 15m |
     | Endpoint | http://localhost:8080 |
     | Container | nanoclaw |
     ```
   - If stopped:
     ```
     ## NanoClaw Status

     NanoClaw is not running. Start it with `/nanoclaw start`.
     ```

---

## Subcommand: logs

1. Parse the optional line count from $ARGUMENTS (default: 50). Extract the number after "logs".

2. Fetch logs:
   ```bash
   docker compose -f "$COMPOSE_FILE" logs --tail=N nanoclaw 2>&1
   ```

3. Present the output in a code block:
   ```
   ## NanoClaw Logs (last N lines)
   ```
   Followed by the log output in a fenced code block.

4. If the container is not running, report that and suggest `/nanoclaw start`.

---

## Error Handling

- If Docker is not available: "Docker is not installed or not running. NanoClaw requires Docker Compose v2+."
- If compose file is missing: "No docker-compose.nanoclaw.yml found. Run `/configure-nanoclaw` first."
- If the container fails to start, show the last 20 lines of logs automatically.
- If any command fails, show the error output and suggest next steps.
