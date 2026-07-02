FROM pufferpanel/pufferpanel:latest

# Install curl
USER root
RUN apk update && apk add --no-cache curl

# Download ngrok, extract it safely, and make it executable
RUN curl -sSL -o /tmp/ngrok.tgz https://bin.equinox.io/c/bPf3oKqgD2j/ngrok-v3-stable-linux-amd64.tgz && \
    tar -xzf /tmp/ngrok.tgz -C /usr/local/bin && \
    rm /tmp/ngrok.tgz

# Set mandatory web port for Hugging Face UI
ENV PUFFER_PANEL_WEB_PORT=7860
EXPOSE 7860

# Custom startup script
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