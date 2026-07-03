#!/bin/bash
set -e

ngrok config add-authtoken "$NGROK_AUTHTOKEN"

cd /crafty
python3 main.py &
CRAFTY_PID=$!

sleep 10

ngrok start --all --config /app/tunnels.yml --log=stdout &

SECRET_KEY="$PLAYIT_SECRET" playit &

wait $CRAFTY_PID