FROM pufferpanel/pufferpanel:latest

# Switch to root to install dependencies
USER root

# Install curl and unzip
RUN apk update && apk add --no-cache curl unzip

# Download and install ngrok
RUN curl -sSL -o /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip && \
    unzip /tmp/ngrok.zip -d /usr/local/bin && \
    rm /tmp/ngrok.zip

ENV PUFFER_PANEL_WEB_PORT=7860
EXPOSE 7860

# Custom startup script
CMD ["/bin/sh", "-c", "\
    # 1. Force-create a structural config that defines the local node as 'local/standalone' \
    mkdir -p /etc/pufferpanel; \
    echo '{\
      \"panel\": {\"web\": {\"host\": \"0.0.0.0:7860\"}},\
      \"daemon\": {\
        \"data\": {\"servers\": \"/var/lib/pufferpanel/servers\"},\
        \"sftp\": {\"host\": \"0.0.0.0:5657\"}\
      }\
    }' > /etc/pufferpanel/config.json; \
    \
    # 2. Tell the internal PufferPanel node manager to use local execution instead of docker \
    echo '{\
      \"images\": {},\
      \"environments\": {\"local\": {}},\
      \"active\": true\
    }' > /etc/pufferpanel/local.json; \
    \
    # 3. Add PufferPanel admin user (suppressing errors if it already exists) \
    /pufferpanel/pufferpanel user add --name admin --email admin@hf.space --password Password123! --admin true || true; \
    \
    # 4. Start ngrok TCP tunnel if an Authtoken is provided \
    if [ -n \"$NGROK_AUTHTOKEN\" ]; then \
        echo 'Starting ngrok TCP tunnel for Minecraft on port 25565...'; \
        ngrok config add-authtoken \"$NGROK_AUTHTOKEN\"; \
        ngrok tcp 25565 --log=stdout & \
    else \
        echo 'WARNING: NGROK_AUTHTOKEN not found. Server won\'t be accessible externally.'; \
    fi; \
    \
    # 5. Run PufferPanel with an explicit flag telling it not to auto-create a docker daemon \
    /pufferpanel/pufferpanel run \
"]