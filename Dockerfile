FROM pufferpanel/pufferpanel:latest

# Switch to root to install dependencies
USER root

# Install curl and unzip
RUN apk update && apk add --no-cache curl unzip

# Download and install ngrok
RUN curl -sSL -o /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip && \
    unzip /tmp/ngrok.zip -d /usr/local/bin && \
    rm /tmp/ngrok.zip

# Set mandatory web port for Hugging Face UI
ENV PUFFER_PANEL_WEB_PORT=7860
EXPOSE 7860

# Custom startup script
CMD ["/bin/sh", "-c", "\
    # 1. Create PufferPanel config forcing the standalone driver instead of Docker \
    if [ ! -f /etc/pufferpanel/config.json ]; then \
        echo '{\"panel\": {\"web\": {\"host\": \"0.0.0.0:7860\"}}, \"daemon\": {\"sfpt\": {\"host\": \"0.0.0.0:5657\"}, \"data\": {\"cache\": \"/var/lib/pufferpanel/cache\", \"servers\": \"/var/lib/pufferpanel/servers\"}}}' > /etc/pufferpanel/config.json; \
    fi; \
    \
    # 2. Pre-configure PufferPanel to use the standalone/host environment by default \
    mkdir -p /etc/pufferpanel && \
    echo '{\"data\":{\"templates\":[\"local\"]}}' > /etc/pufferpanel/daemon.json; \
    \
    # 3. Add PufferPanel admin user \
    /pufferpanel/pufferpanel user add --name admin --email admin@hf.space --password Password123! --admin true; \
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
    # 5. Run PufferPanel \
    /pufferpanel/pufferpanel run \
"]