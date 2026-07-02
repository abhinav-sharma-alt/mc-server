#!/bin/bash
set -e

# Authenticate ngrok
ngrok config add-authtoken "$NGROK_AUTHTOKEN"

mkdir -p /etc/pufferpanel

# Generate PufferPanel configuration targeting Hugging Face's port and bypassing WebAuthn crashes
if [ ! -f /etc/pufferpanel/config.json ]; then
  echo '{"panel":{"web":{"host":"0.0.0.0:7860"},"webauthn":{"id":"huggingface.co","name":"HuggingFace Space","origin":"https://huggingface.co"}},"daemon":{"data":{"servers":"/var/lib/pufferpanel/servers"},"sftp":{"host":"0.0.0.0:5657"}}}' > /etc/pufferpanel/config.json
fi

# Run PufferPanel directly using its core execution command
pufferpanel run &
PUFFER_PID=$!

sleep 8

# Create the admin account securely
if [ ! -f /etc/pufferpanel/.admin_created ]; then
  pufferpanel user add \
    --name "$PUFFER_ADMIN_USER" \
    --email "$PUFFER_ADMIN_EMAIL" \
    --password "$PUFFER_ADMIN_PASS" \
    --admin true || true
  touch /etc/pufferpanel/.admin_created
fi

# Start all tunnels matching your configuration schema
ngrok start --all \
  --config /app/tunnels.yml \
  --log=stdout &

wait $PUFFER_PID