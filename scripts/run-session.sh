#!/bin/bash

# Ignore file-mode-only changes (e.g. chmod +x on this script) so they never
# count as a "dirty tree" diff and block a git pull --rebase later.
git config core.fileMode false

SESSION_MINUTES=345   # 5h45m — leaves buffer for the commit step after this

# Small retrying push for the console/ signal-file commits made throughout
# this script. These files are ephemeral (not world data), so on conflict we
# always just take our own version of console/* and retry — never worth
# aborting a running session over a signal-file race.
push_console_state() {
  for attempt in 1 2 3; do
    if git push origin HEAD:main --quiet 2>/dev/null; then
      return 0
    fi
    git fetch origin main --quiet 2>/dev/null
    if git rebase origin/main --quiet 2>/dev/null; then
      continue
    fi
    for f in $(git diff --name-only --diff-filter=U 2>/dev/null); do
      git checkout --ours -- "$f" 2>/dev/null
      git add "$f" 2>/dev/null
    done
    GIT_EDITOR=true git rebase --continue --quiet 2>/dev/null || { git rebase --abort 2>/dev/null || true; }
  done
  echo "WARNING: could not push console state after retries (non-fatal, will retry next poll)."
  return 1
}

if [ -z "$PLAYIT_SECRET" ]; then
  echo "ERROR: PLAYIT_SECRET is not set. Add it as a GitHub Actions secret."
  exit 1
fi

echo "Starting playit.gg agent via Docker..."
docker run -d --net=host \
  -e SECRET_KEY="$PLAYIT_SECRET" \
  --name playit-agent \
  ghcr.io/playit-cloud/playit-agent:0.17

sleep 5
echo "--- playit container status ---"
docker ps -a --filter "name=playit-agent"
echo "--- playit container logs (immediate) ---"
docker logs playit-agent 2>&1 || true
echo "--- end immediate logs ---"

sleep 15
echo "--- playit container logs (after wait) ---"
PLAYIT_LOGS=$(docker logs playit-agent 2>&1)
echo "$PLAYIT_LOGS"
echo "--- end logs ---"

SERVER_PORT="${SERVER_PORT:-25565}"

# The tunnel address comes from modpacks/<name>/meta.json (set via
# /modpack configure name: X tunnel_address: <address>), passed in as the
# TUNNEL_ADDRESS env var by start-server.yml. It just needs to be pointed at
# local port $SERVER_PORT in the playit.gg dashboard for this agent — it does
# NOT need to be globally unique across modpacks, since each session runs on
# its own isolated GitHub Actions runner.
if [ -z "$TUNNEL_ADDRESS" ]; then
  echo "ERROR: No tunnel_address configured for this modpack."
  echo "Set one with: /modpack configure name: <modpack> tunnel_address: <address playit gave you>"
  echo "Make sure that tunnel is pointed at local port $SERVER_PORT in the playit.gg dashboard."
  exit 1
fi
echo "Using tunnel address: $TUNNEL_ADDRESS -> local port $SERVER_PORT"

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🟢 **Minecraft server is UP**\\nConnect at: \`$TUNNEL_ADDRESS\`\\nSession will run for ~5h45m.\\nRun log: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\"}" \
    "$DISCORD_WEBHOOK"
fi

echo "Starting Minecraft server..."
cd server

# Remove RCON config if present from earlier attempts — not used anymore
sed -i '/^enable-rcon=/d; /^rcon.port=/d; /^rcon.password=/d' server.properties 2>/dev/null

# Set up a FIFO so we can feed console commands into the server's stdin
mkfifo /tmp/mc_console 2>/dev/null || true
exec 3<>/tmp/mc_console

MEMORY_GB="${MEMORY_GB:-10}"
SERVER_JAR="${SERVER_JAR:-server.jar}"
LAUNCH_MODE="${LAUNCH_MODE:-jar}"
START_SCRIPT="${START_SCRIPT:-start.sh}"
LOG_FILE="server/logs/latest.log"   # standard log4j location for vanilla/Paper/Forge/Fabric; path is relative to the repo root, since callers run from there after the cd .. below

# Sends the real in-game "stop" command through stdin (not an OS signal) and
# waits for the process to exit. This is what actually persists things like
# gamerules (fallDamage, keepInventory, ...) which live in level.dat and are
# only guaranteed to be flushed by a clean in-game shutdown.
#
# We deliberately do NOT rely on kill -SIGTERM as the primary mechanism: in
# `script` launch_mode, $MC_PID is the wrapper script's PID, and if that
# wrapper doesn't `exec` into java (many Forge/NeoForge start.sh scripts spawn
# java as a child instead), SIGTERM kills the wrapper without ever reaching
# the actual server process — so it never saves, and the world gets copied
# out mid-write on the next commit. Typing "stop" into stdin has no such
# problem: every launcher forwards stdin to the real server process.
graceful_stop() {
  local wait_seconds="${1:-60}"
  echo "Sending 'stop' to the server console and waiting up to ${wait_seconds}s..."
  { echo "save-all flush"; sleep 1; echo "stop"; } >&3 2>/dev/null || true

  for i in $(seq 1 "$wait_seconds"); do
    kill -0 "$MC_PID" 2>/dev/null || { echo "Server exited cleanly."; return 0; }
    sleep 1
  done

  echo "Server didn't exit after 'stop' within ${wait_seconds}s — escalating to SIGTERM."
  kill -SIGTERM "$MC_PID" 2>/dev/null || true
  for i in $(seq 1 15); do
    kill -0 "$MC_PID" 2>/dev/null || { echo "Server exited after SIGTERM."; return 0; }
    sleep 1
  done

  echo "Server still alive — forcing SIGKILL. Any unsaved changes since the last autosave will be lost."
  kill -SIGKILL "$MC_PID" 2>/dev/null || true
}

if [ "$LAUNCH_MODE" = "script" ]; then
  # Forge-style packs often read memory from user_jvm_args.txt rather than
  # taking -Xmx as a start.sh argument. If that file exists, rewrite its
  # -Xmx line (or add one) so MEMORY_GB actually takes effect.
  if [ -f "user_jvm_args.txt" ]; then
    sed -i '/-Xmx/d' user_jvm_args.txt
    echo "-Xmx${MEMORY_GB}G" >> user_jvm_args.txt
  fi
  ./"$START_SCRIPT" nogui <&3 &
else
  java -Xmx${MEMORY_GB}G -Xms1G -jar "$SERVER_JAR" nogui <&3 &
fi
MC_PID=$!
cd ..

# Make sure the console command/stop files exist and start CLEAR for this session
mkdir -p console
echo -n "" > console/command.txt
echo -n "" > console/stop.txt
git add console/command.txt console/stop.txt
git commit -m "console: reset signal files for new session" --quiet 2>/dev/null || true
push_console_state || true

# Background loop: poll GitHub for new console commands AND a stop signal
poll_console() {
  sleep 20   # give the server time to fully boot before accepting any signals
  LAST_EXECUTED_ID=""
  while kill -0 "$MC_PID" 2>/dev/null; do
    git fetch origin main --quiet
    # Fully sync to origin's tip (not just checkout individual files) so our
    # own commits below always build on the latest base and push cleanly —
    # `checkout origin/main -- <path>` alone updates the working tree but
    # never advances local history, which made every subsequent push here a
    # guaranteed non-fast-forward whenever origin had moved (e.g. right
    # after a command was queued) and could snowball into a stuck loop.
    git reset --hard origin/main --quiet

    if [ -s console/command.txt ]; then
      CMD_ID=$(sed -n '1p' console/command.txt)
      CMD=$(sed -n '2p' console/command.txt)

      if [ "$CMD_ID" = "$LAST_EXECUTED_ID" ]; then
        # Same command id we already ran — our clear of this file just
        # hasn't landed on origin yet (push race). Do NOT re-execute it.
        :
      else
        echo "Executing console command: $CMD"

        LINES_BEFORE=0
        [ -f "$LOG_FILE" ] && LINES_BEFORE=$(wc -l < "$LOG_FILE")

        echo "$CMD" >&3
        LAST_EXECUTED_ID="$CMD_ID"
        echo -n "" > console/command.txt
        git add console/command.txt
        git commit -m "console: executed command" --quiet 2>/dev/null
        push_console_state || true

        # Give the server a moment to process the command and write its
        # response to the log, then relay any new lines back to Discord.
        # Note: slow/async commands (e.g. big worldgen ops) may log after
        # this window and won't be captured — this covers typical commands.
        sleep 2
        if [ -n "$DISCORD_WEBHOOK" ]; then
          if [ -f "$LOG_FILE" ]; then
            LINES_AFTER=$(wc -l < "$LOG_FILE")
            NEW_LINES=$((LINES_AFTER - LINES_BEFORE))
            if [ "$NEW_LINES" -gt 0 ]; then
              OUTPUT=$(tail -n "$NEW_LINES" "$LOG_FILE" | tail -c 1500)
            else
              OUTPUT="(no output)"
            fi
          else
            OUTPUT="(log file not found)"
          fi
          PAYLOAD=$(jq -n --arg cmd "$CMD" --arg out "$OUTPUT" \
            '{content: ("📤 `" + $cmd + "`\n```\n" + $out + "\n```")}')
          curl -s -H "Content-Type: application/json" -d "$PAYLOAD" "$DISCORD_WEBHOOK" > /dev/null
        fi
      fi
    fi

    if [ -s console/stop.txt ]; then
      echo "Graceful stop signal received — shutting down..."
      echo -n "" > console/stop.txt
      git add console/stop.txt
      git commit -m "console: stop signal consumed" --quiet
      push_console_state || true

      graceful_stop 30
      break
    fi

    sleep 5
  done
}
poll_console &
POLL_PID=$!

echo "Session running for up to $SESSION_MINUTES minutes (or until a graceful stop is triggered)..."
END_TIME=$((SECONDS + SESSION_MINUTES * 60))
while kill -0 "$MC_PID" 2>/dev/null && [ $SECONDS -lt $END_TIME ]; do
  sleep 5
done

if kill -0 "$MC_PID" 2>/dev/null; then
  echo "Time's up — stopping server gracefully..."
  graceful_stop 60
fi
wait $MC_PID 2>/dev/null || true

# Stop the console poller gracefully instead of hard-killing it, so it isn't
# caught mid-write/mid-commit on a tracked file (which left the working tree
# dirty and broke the final "git pull --rebase" step in the workflow).
if [ -n "$POLL_PID" ] && kill -0 "$POLL_PID" 2>/dev/null; then
  echo "Stopping console poller (pid $POLL_PID)..."
  kill -TERM "$POLL_PID" 2>/dev/null || true
  for i in $(seq 1 10); do
    kill -0 "$POLL_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$POLL_PID" 2>/dev/null; then
    echo "Poller didn't exit in time — forcing kill."
    kill -9 "$POLL_PID" 2>/dev/null || true
  fi
fi

exec 3>&- 2>/dev/null || true

docker stop playit-agent || true
docker rm playit-agent || true

# Safety net: if the poller left any tracked console files modified but
# uncommitted (e.g. it was interrupted between writing and committing),
# clean that up now so the workflow's later "git pull --rebase" step
# doesn't fail on a dirty tree.
if [ -n "$(git status --porcelain console/ 2>/dev/null)" ]; then
  echo "Cleaning up leftover console file state..."
  git add console/
  git commit -m "console: final state cleanup" --quiet 2>/dev/null || true
  push_console_state || true
fi

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🔴 **Minecraft server is DOWN**\\nSession ended (was: \`$TUNNEL_ADDRESS\`)\\nWorld has been saved back to the repo.\"}" \
    "$DISCORD_WEBHOOK"
fi