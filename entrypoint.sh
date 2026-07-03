#!/bin/bash
set -e

ngrok config add-authtoken "$NGROK_AUTHTOKEN"
mkdir -p /etc/pufferpanel /var/lib/pufferpanel

rm -f /var/lib/pufferpanel/pufferpanel.db
rm -f /etc/pufferpanel/.admin_created

echo '{"panel":{"web":{"host":"0.0.0.0:7860"},"webauthn":{"id":"'"${NGROK_DOMAIN}"'","name":"PufferPanel","origin":"https://'"${NGROK_DOMAIN}"'"}},"daemon":{"data":{"servers":"/var/lib/pufferpanel/servers"},"sftp":{"host":"0.0.0.0:5657"}}}' > /etc/pufferpanel/config.json

pufferpanel run &
PUFFER_PID=$!
sleep 6

pufferpanel user add \
  --name "$PUFFER_ADMIN_USER" \
  --email "$PUFFER_ADMIN_EMAIL" \
  --password "$PUFFER_ADMIN_PASS" \
  --admin
touch /etc/pufferpanel/.admin_created

ngrok start --all --config /app/tunnels.yml --log=stdout &

SECRET_KEY="$PLAYIT_SECRET" playit &

wait $PUFFER_PID