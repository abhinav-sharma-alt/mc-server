FROM alpine:3.19

# 1. Install dependencies, Java 17 (for Minecraft), and ngrok
USER root
RUN apk update && apk add --no-cache \
    curl \
    unzip \
    openjdk17-jre-headless \
    git \
    openssl

# 2. Download and install ngrok
RUN curl -sSL -o /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip && \
    unzip /tmp/ngrok.zip -d /usr/local/bin && \
    rm /tmp/ngrok.zip

# 3. Download the standalone PufferPanel Linux binary
RUN mkdir -p /pufferpanel && \
    curl -sSL -o /pufferpanel/pufferpanel https://github.com/PufferPanel/PufferPanel/releases/latest/download/pufferpanel_linux_amd64 && \
    chmod +x /pufferpanel/pufferpanel

# Configure standard environmental paths
ENV PUFFER_PANEL_WEB_PORT=7860
EXPOSE 7860

# 4. Bootstrap configurations cleanly bypassing Docker definitions
CMD ["/bin/sh", "-c", "\
    mkdir -p /etc/pufferpanel /var/lib/pufferpanel/servers /var/log/pufferpanel; \
    \
    # Create config missing any mention of docker nodes \
    echo '{\
      \"panel\": {\"web\": {\"host\": \"0.0.0.0:7860\"}},\
      \"daemon\": {\
        \"data\": {\"servers\": \"/var/lib/pufferpanel/servers\"},\
        \"sftp\": {\"host\": \"0.0.0.0:5657\"}\
      }\
    }' > /etc/pufferpanel/config.json; \
    \
    # Add the local user profile \
    /pufferpanel/pufferpanel user add --name admin --email admin@hf.space --password Password123! --admin true || true; \
    \
    # Start ngrok tunnel \
    if [ -n \"$NGROK_AUTHTOKEN\" ]; then \
        echo 'Starting ngrok TCP tunnel...'; \
        ngrok config add-authtoken \"$NGROK_AUTHTOKEN\"; \
        ngrok tcp 25565 --log=stdout & \
    fi; \
    \
    # Launch the panel directly \
    exec /pufferpanel/pufferpanel run \
"]