#!/bin/bash
set -e

ngrok config add-authtoken "$NGROK_AUTHTOKEN"

export PUFFERPANEL_PANEL_SETTINGS_MASTERURL="https://${NGROK_DOMAIN}"

pufferpanel runService --workDir /etc/pufferpanel &
PUFFER_PID=$!

sleep 5

ngrok start --all \
  --config "$(ngrok config check 2>&1 | grep -oP '(?<=at ).*')" \
  --config /app/tunnels.yml \
  --log=stdout &

wait $PUFFER_PID