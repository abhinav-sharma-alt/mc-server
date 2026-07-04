#!/bin/bash

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

TUNNEL_ADDRESS=$(echo "$PLAYIT_LOGS" | grep -oE '[a-zA-Z0-9.-]+\.(joinmc\.link|playit\.gg)(:[0-9]+)?' | head -n1)

if [ -z "$TUNNEL_ADDRESS" ]; then
  TUNNEL_ADDRESS="(couldn't auto-detect — check the playit.gg dashboard or this run's log)"
fi

echo "Detected tunnel address: $TUNNEL_ADDRESS"

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🟢 **Minecraft server is UP**\\nConnect at: \`$TUNNEL_ADDRESS\`\\nSession will run for ~5h45m.\\nRun log: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\"}" \
    "$DISCORD_WEBHOOK"
fi

echo "Starting Minecraft server..."
cd server
java -Xmx3G -Xms1G -jar server.jar nogui &
MC_PID=$!
cd ..

echo "Session running for $SESSION_MINUTES minutes..."
sleep $((SESSION_MINUTES * 60))

echo "Time's up — stopping server gracefully..."
kill -SIGTERM $MC_PID
wait $MC_PID || true

docker stop playit-agent || true
docker rm playit-agent || true

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🔴 **Minecraft server is DOWN**\\nSession ended (was: \`$TUNNEL_ADDRESS\`)\\nWorld has been saved back to the repo.\"}" \
    "$DISCORD_WEBHOOK"
fi