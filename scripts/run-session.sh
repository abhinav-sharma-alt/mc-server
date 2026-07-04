#!/bin/bash

# Ignore file-mode-only changes (e.g. chmod +x on this script) so they never
# count as a "dirty tree" diff and block a git pull --rebase later.
git config core.fileMode false

SESSION_MINUTES=345   # 5h45m — leaves buffer for the commit step after this

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

TUNNEL_ADDRESS="significant-surpass.gl.joinmc.link"
echo "Using configured tunnel address: $TUNNEL_ADDRESS"

echo "Detected tunnel address: $TUNNEL_ADDRESS"

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
java -Xmx${MEMORY_GB}G -Xms1G -jar "$SERVER_JAR" nogui <&3 &
MC_PID=$!
cd ..

# Make sure the console command/stop files exist and start CLEAR for this session
mkdir -p console
echo -n "" > console/command.txt
echo -n "" > console/stop.txt
git add console/command.txt console/stop.txt
git commit -m "console: reset signal files for new session" --quiet 2>/dev/null || true
git push origin HEAD:main --quiet 2>/dev/null || true

# Background loop: poll GitHub for new console commands AND a stop signal
poll_console() {
  sleep 20   # give the server time to fully boot before accepting any signals
  while kill -0 "$MC_PID" 2>/dev/null; do
    git fetch origin main --quiet
    git checkout origin/main -- console/command.txt 2>/dev/null || true
    git checkout origin/main -- console/stop.txt 2>/dev/null || true

    if [ -s console/command.txt ]; then
      CMD=$(cat console/command.txt)
      echo "Executing console command: $CMD"
      echo "$CMD" >&3
      echo -n "" > console/command.txt
      git add console/command.txt
      git commit -m "console: executed command" --quiet 2>/dev/null
      git pull --rebase --autostash --quiet 2>/dev/null
      git push origin HEAD:main --quiet 2>/dev/null
    fi

    if [ -s console/stop.txt ]; then
      echo "Graceful stop signal received — shutting down..."
      echo -n "" > console/stop.txt
      git add console/stop.txt
      git commit -m "console: stop signal consumed" --quiet
      git pull --rebase --autostash --quiet
      git push origin HEAD:main --quiet

      echo "stop" >&3

      # Wait up to 30s for the server to actually exit; force-kill if it doesn't
      for i in $(seq 1 30); do
        if ! kill -0 "$MC_PID" 2>/dev/null; then
          echo "Server exited cleanly after stop command."
          break
        fi
        sleep 1
      done
      if kill -0 "$MC_PID" 2>/dev/null; then
        echo "Server didn't exit after 'stop' command — forcing SIGTERM."
        kill -SIGTERM "$MC_PID"
      fi
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
  kill -SIGTERM $MC_PID
fi
wait $MC_PID || true

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
  git pull --rebase --autostash --quiet 2>/dev/null || git rebase --abort 2>/dev/null || true
  git push origin HEAD:main --quiet 2>/dev/null || true
fi

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🔴 **Minecraft server is DOWN**\\nSession ended (was: \`$TUNNEL_ADDRESS\`)\\nWorld has been saved back to the repo.\"}" \
    "$DISCORD_WEBHOOK"
fi