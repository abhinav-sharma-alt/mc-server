#!/bin/bash
set -e

# Authenticate ngrok
ngrok config add-authtoken "$NGROK_AUTHTOKEN"

mkdir -p /etc/pufferpanel /var/lib/pufferpanel

# 1. FORCE A FRESH DATABASE SLATE
# PufferPanel stores users in a local SQLite file (pufferpanel.db).
# Wiping it forces the app to rebuild the schema clean on boot.
echo "Clearing old database records to reset credentials..."
rm -f /var/lib/pufferpanel/pufferpanel.db
rm -f /etc/pufferpanel/.admin_created

# 2. Generate clean configuration
echo '{"panel":{"web":{"host":"0.0.0.0:7860"},"webauthn":{"id":"huggingface.co","name":"HuggingFace Space","origin":"https://huggingface.co"}},"daemon":{"data":{"servers":"/var/lib/pufferpanel/servers"},"sftp":{"host":"0.0.0.0:5657"}}}' > /etc/pufferpanel/config.json

# 3. Start PufferPanel background service
pufferpanel run &
PUFFER_PID=$!

# Give the app a moment to generate the fresh database file
sleep 6

# 4. Inject the fresh admin profile cleanly
echo "Registering fresh admin account..."
pufferpanel user add \
  --name "$PUFFER_ADMIN_USER" \
  --email "$PUFFER_ADMIN_EMAIL" \
  --password "$PUFFER_ADMIN_PASS" \
  --admin

touch /etc/pufferpanel/.admin_created
echo "Admin profile successfully created!"

# 5. Start all tunnels matching your configuration schema
ngrok start --all \
  --config /app/tunnels.yml \
  --log=stdout &

wait $PUFFER_PID