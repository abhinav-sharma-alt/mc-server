FROM pufferpanel/pufferpanel:latest

# Switch to root to install dependencies
USER root

# Install curl and unzip
RUN apk update && apk add --no-cache curl unzip

# Download and install ngrok
RUN curl -sSL -o /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip && \
    unzip /tmp/ngrok.zip -d /usr/local/bin && \
    rm /tmp/ngrok.zip

# 1. FORCE PUFFERPANEL ENVIRONMENT OVERRIDES
# These environment variables tell the daemon to run standalone instead of trying to look for a Docker socket
ENV PUFFER_PANEL_WEB_PORT=7860
ENV PUFFER_DAEMON_ENV_TYPE=standard
ENV PUFFER_DAEMON_ENV_PROVIDER=local

EXPOSE 7860

# Custom startup script
CMD ["/bin/sh", "-c", "\
    # 2. Add PufferPanel admin user \
    /pufferpanel/pufferpanel user add --name admin --email admin@hf.space --password Password123! --admin true; \
    \
    # 3. Start ngrok TCP tunnel if an Authtoken is provided \
    if [ -n \"$NGROK_AUTHTOKEN\" ]; then \
        echo 'Starting ngrok TCP tunnel for Minecraft on port 25565...'; \
        ngrok config add-authtoken \"$NGROK_AUTHTOKEN\"; \
        ngrok tcp 25565 --log=stdout & \
    else \
        echo 'WARNING: NGROK_AUTHTOKEN not found. Server won\'t be accessible externally.'; \
    fi; \
    \
    # 4. Run PufferPanel \
    /pufferpanel/pufferpanel run \
"]