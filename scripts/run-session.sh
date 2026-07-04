#!/bin/bash

SESSION_MINUTES=345   # 5h45m — leaves buffer for the commit step after this

if [ -z "$NGROK_AUTHTOKEN" ]; then
  echo "ERROR: NGROK_AUTHTOKEN is not set. Add it as a GitHub Actions secret."
  exit 1
fi

echo "Starting ngrok tunnel via Docker..."
docker run -d --rm --net=host \
  -e NGROK_AUTHTOKEN="$NGROK_AUTHTOKEN" \
  --name ngrok-agent \
  ngrok/ngrok:latest tcp 25565

# Give ngrok time to establish the tunnel
sleep 10

echo "--- ngrok container logs ---"
docker logs ngrok-agent 2>&1 || true
echo "--- end logs ---"

# Retry the API query a few times in case it's just slow to come up
TUNNEL_JSON=""
for i in 1 2 3 4 5; do
  TUNNEL_JSON=$(curl -s --max-time 5 http://localhost:4040/api/tunnels || echo "")
  if [ -n "$TUNNEL_JSON" ]; then
    break
  fi
  echo "ngrok API not ready yet, retrying... ($i/5)"
  sleep 5
done

if [ -z "$TUNNEL_JSON" ]; then
  echo "ERROR: Could not reach ngrok's local API after retries. Dumping logs again:"
  docker logs ngrok-agent 2>&1 || true
  TUNNEL_ADDRESS="(ngrok failed to start — check the run log above)"
else
  TUNNEL_ADDRESS=$(echo "$TUNNEL_JSON" | jq -r '.tunnels[0].public_url' | sed 's|tcp://||')
  if [ -z "$TUNNEL_ADDRESS" ] || [ "$TUNNEL_ADDRESS" == "null" ]; then
    TUNNEL_ADDRESS="(couldn't parse tunnel address — check this run's log)"
    echo "$TUNNEL_JSON"
  fi
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

docker stop ngrok-agent || true

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"🔴 **Minecraft server is DOWN**\\nSession ended (was: \`$TUNNEL_ADDRESS\`)\\nWorld has been saved back to the repo.\"}" \
    "$DISCORD_WEBHOOK"
fi