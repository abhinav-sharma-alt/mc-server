FROM pufferpanel/pufferpanel:latest

# Install curl to download ngrok
USER root
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Download and install ngrok
RUN curl -s https://bin.equinox.io/c/bPf3oKqgD2j/ngrok-stable-linux-amd64.tgz | tar -xz -C /usr/local/bin

# Set mandatory web port for Hugging Face UI
ENV PUFFER_PANEL_WEB_PORT=7860
EXPOSE 7860

# We use a custom startup script to start both PufferPanel and ngrok simultaneously
CMD ["/bin/sh", "-c", "\
    # 1. Create PufferPanel default config \
    if [ ! -f /etc/pufferpanel/config.json ]; then \
        echo '{\"panel\": {\"web\": {\"host\": \"0.0.0.0:7860\"}}}' > /etc/pufferpanel/config.json; \
    fi; \
    \
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