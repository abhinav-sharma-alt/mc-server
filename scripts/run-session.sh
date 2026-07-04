#!/bin/bash
set -e

SESSION_MINUTES=345   # 5h45m — leaves buffer for the commit step after this

if [ -z "$PLAYIT_SECRET" ]; then
  echo "ERROR: PLAYIT_SECRET is not set. Add it as a GitHub Actions secret."
  exit 1
fi

echo "Starting playit.gg agent via Docker..."
docker run -d --rm --net=host \
  -e SECRET_KEY="$PLAYIT_SECRET" \
  --name playit-agent \
  ghcr.io/playit-cloud/playit-agent:0.17

# Give playit a moment to establish the tunnel
sleep 15

echo "playit.gg agent started. Find your assigned address in your playit.gg dashboard at https://playit.gg"

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d '{"content": "🟢 Minecraft server session starting! Check the playit.gg dashboard for the connect address, or watch this run'"'"'s log: '"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"'"}' \
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

if [ -n "$DISCORD_WEBHOOK" ]; then
  curl -H "Content-Type: application/json" \
    -d '{"content": "🔴 Minecraft server session ended. World has been saved back to the repo."}' \
    "$DISCORD_WEBHOOK"
fi
