FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y \
    curl unzip git build-essential default-jdk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /crafty
RUN git clone --depth 1 https://gitlab.com/crafty-controller/crafty-4.git . \
    && pip install --break-system-packages -r requirements.txt

# ngrok, for the panel
RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok

# playit, for the game port
RUN curl -SsL -o /usr/local/bin/playit \
    https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 \
    && chmod +x /usr/local/bin/playit

RUN mkdir -p /crafty/app/config /crafty/backups /crafty/servers \
    && chmod -R 777 /crafty

COPY tunnels.yml /app/tunnels.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8443
ENTRYPOINT ["/entrypoint.sh"]