#!/bin/bash
set -e

# Authenticate ngrok
ngrok config add-authtoken "$NGROK_AUTHTOKEN"

mkdir -p /etc/pufferpanel

# Generate PufferPanel configuration
if [ ! -f /etc/pufferpanel/config.json ]; then
  echo '{"panel":{"web":{"host":"0.0.0.0:7860"},"webauthn":{"id":"huggingface.co","name":"HuggingFace Space","origin":"https://huggingface.co"}},"daemon":{"data":{"servers":"/var/lib/pufferpanel/servers"},"sftp":{"host":"0.0.0.0:5657"}}}' > /etc/pufferpanel/config.json
fi

# Run PufferPanel directly
pufferpanel run &
PUFFER_PID=$!

sleep 5

# --- FORCE RESET ADMIN ACCOUNT ---
# We delete the marker file and use a subshell to force-add the user clean
rm -f /etc/pufferpanel/.admin_created

echo "Creating/Resetting admin user..."
pufferpanel user add \
  --name "$PUFFER_ADMIN_USER" \
  --email "$PUFFER_ADMIN_EMAIL" \
  --password "$PUFFER_ADMIN_PASS" \
  --admin || echo "Admin user profile updated or already exists."

touch /etc/pufferpanel/.admin_created
# ----------------------------------

# Start all tunnels matching your configuration schema
ngrok start --all \
  --config /app/tunnels.yml \
  --log=stdout &

wait $PUFFER_PID