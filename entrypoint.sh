#!/bin/bash
set -e

# ngrok needs its authtoken — pull from HF Space secret
ngrok config add-authtoken "$NGROK_AUTHTOKEN"

# Start PufferPanel in the background
pufferpanel --dir /etc/pufferpanel &
PUFFER_PID=$!

# Give it a second to bind port 8080
sleep 5

# Tunnel the web panel out (free plan = 1 tunnel)
ngrok http 8080 --log=stdout &

wait $PUFFER_PID