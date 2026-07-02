#!/bin/bash
set -e

ngrok config add-authtoken "$NGROK_AUTHTOKEN"

mkdir -p /etc/pufferpanel
if [ ! -f /etc/pufferpanel/config.json ]; then
  echo '{"panel":{"settings":{"masterUrl":"https://'"${NGROK_DOMAIN}"'"}}}' > /etc/pufferpanel/config.json
fi

pufferpanel runService --workDir /etc/pufferpanel &
PUFFER_PID=$!

sleep 5

ngrok start --all \
  --config "$(ngrok config check 2>&1 | grep -oP '(?<=at ).*')" \
  --config /app/tunnels.yml \
  --log=stdout &

wait $PUFFER_PID