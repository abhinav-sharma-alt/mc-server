#!/bin/bash

git config core.fileMode false

JOB_DEADLINE_MINUTES="${JOB_DEADLINE_MINUTES:-335}"
if [ -z "$JOB_START_EPOCH" ]; then JOB_START_EPOCH=$(date +%s); JOB_DEADLINE_MINUTES=345; fi
DEADLINE_EPOCH=$((JOB_START_EPOCH + JOB_DEADLINE_MINUTES * 60))

STOP_MARKER=/tmp/mc_intentional_stop
rm -f "$STOP_MARKER"

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

if [ -z "$TUNNEL_ADDRESS" ]; then
  echo "ERROR: No tunnel_address configured for this modpack."
  echo "Set one with: /modpack configure name: <modpack> tunnel_address: <address playit gave you>"
  echo "Make sure that tunnel is pointed at local port $SERVER_PORT in the playit.gg dashboard."
  exit 1
fi
echo "Using tunnel address: $TUNNEL_ADDRESS -> local port $SERVER_PORT"
SESSION_LEFT_MIN=$(( (DEADLINE_EPOCH - $(date +%s)) / 60 ))
SESSION_HM="$((SESSION_LEFT_MIN / 60))h$((SESSION_LEFT_MIN % 60))m"

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🟢 **Minecraft server is UP**\\nConnect at: \`$TUNNEL_ADDRESS\`\\nSession will run for ~${SESSION_HM}.\\nRun log: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\"}" \
    "$DISCORD_WEBHOOK"
fi

echo "Starting Minecraft server..."
cd server

sed -i '/^enable-rcon=/d; /^rcon.port=/d; /^rcon.password=/d' server.properties 2>/dev/null

mkfifo /tmp/mc_console 2>/dev/null || true
exec 3<>/tmp/mc_console

MEMORY_GB="${MEMORY_GB:-10}"
SERVER_JAR="${SERVER_JAR:-server.jar}"
LAUNCH_MODE="${LAUNCH_MODE:-jar}"
START_SCRIPT="${START_SCRIPT:-start.sh}"
LOG_FILE="server/logs/latest.log"

graceful_stop() {
  local wait_seconds="${1:-60}"
  touch "$STOP_MARKER"
  echo "Sending 'stop' to the server console and waiting up to ${wait_seconds}s..."
  echo "stop" >&3 2>/dev/null || true

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
  if [ -f "user_jvm_args.txt" ]; then
    sed -i '/-Xmx/d' user_jvm_args.txt
    echo "-Xmx${MEMORY_GB}G" >> user_jvm_args.txt
  fi
  ./"$START_SCRIPT" nogui <&3 &
else
  if [ "$SOURCE_TYPE" = "paper" ]; then
    JAVA_OPTS=(-Xms${MEMORY_GB}G -Xmx${MEMORY_GB}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled
      -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC
      -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40
      -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5
      -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15
      -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5
      -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1)
  else
    JAVA_OPTS=(-Xmx${MEMORY_GB}G -Xms1G)
  fi
  java "${JAVA_OPTS[@]}" -jar "$SERVER_JAR" nogui <&3 &
fi
MC_PID=$!
cd ..

mkdir -p console
echo -n "" > console/command.txt
echo -n "" > console/stop.txt
git add console/command.txt console/stop.txt
git commit -m "console: reset signal files for new session" --quiet 2>/dev/null || true
push_console_state || true

poll_console() {
  sleep 20
  LAST_EXECUTED_ID=""
  while kill -0 "$MC_PID" 2>/dev/null; do
    git fetch origin main --quiet
    git merge --ff-only origin/main --quiet 2>/dev/null || true

    if [ -s console/command.txt ]; then
      CMD_ID=$(sed -n '1p' console/command.txt)
      CMD=$(sed -n '2p' console/command.txt)

      if [ "$CMD_ID" = "$LAST_EXECUTED_ID" ]; then
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

echo "Session running until $(date -u -d "@$DEADLINE_EPOCH" +%H:%M:%SZ) (about $(( (DEADLINE_EPOCH - $(date +%s)) / 60 )) minutes), or until a graceful stop is triggered..."
while kill -0 "$MC_PID" 2>/dev/null && [ "$(date +%s)" -lt "$DEADLINE_EPOCH" ]; do
  sleep 5
done

if kill -0 "$MC_PID" 2>/dev/null; then
  echo "Time's up — stopping server gracefully..."
  graceful_stop 60
elif [ ! -f "$STOP_MARKER" ]; then
  echo "::warning::Minecraft server process exited on its own before any stop was requested — this looks like a crash or OOM kill, not a clean shutdown. The world may not have saved properly this session. Check server/crash-reports and server/logs in the uploaded artifact for the cause (e.g. -Xmx${MEMORY_GB}G may be too large for this runner's available memory)."
  if [ -n "$DISCORD_WEBHOOK" ]; then
    curl -s -H "Content-Type: application/json" \
      -d "{\"content\": \"⚠️ **Minecraft server crashed unexpectedly** (not a normal stop). Check the run's crash-reports/logs artifact — the world may not have saved cleanly this session.\"}" \
      "$DISCORD_WEBHOOK" > /dev/null
  fi
fi
wait $MC_PID 2>/dev/null
MC_EXIT_CODE=$?
echo "Server process exit code: $MC_EXIT_CODE"
if [ -f "server/world/level.dat" ]; then
  echo "server/world/level.dat size at shutdown: $(stat -c%s server/world/level.dat 2>/dev/null || echo unknown) bytes"
else
  echo "server/world/level.dat does not exist at shutdown."
fi

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

if [ -n "$(git status --porcelain console/ 2>/dev/null)" ]; then
  echo "Cleaning up leftover console file state..."
  git add console/
  git commit -m "console: final state cleanup" --quiet 2>/dev/null || true
  push_console_state || true
fi

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🔴 **Minecraft server is DOWN**\\nSession ended (was: \`$TUNNEL_ADDRESS\`)\\nWorld is being saved to the world-${MODPACK} release now - wait for the run to finish before starting it again.\"}" \
    "$DISCORD_WEBHOOK"
fi
