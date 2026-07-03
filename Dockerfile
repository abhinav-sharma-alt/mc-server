FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y \
    curl unzip git build-essential default-jdk sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /crafty
RUN git clone --depth 1 https://gitlab.com/crafty-controller/crafty-4.git . \
    && pip install --break-system-packages -r requirements.txt

RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok

RUN curl -SsL -o /usr/local/bin/playit \
    https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 \
    && chmod +x /usr/local/bin/playit

# Create a non-root user, HF Spaces convention uses uid 1000
RUN useradd -m -u 1000 crafty \
    && mkdir -p /crafty/app/config /crafty/backups /crafty/servers \
    && chown -R crafty:crafty /crafty \
    && mkdir -p /home/crafty/.config/ngrok \
    && chown -R crafty:crafty /home/crafty

COPY tunnels.yml /app/tunnels.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown crafty:crafty /entrypoint.sh /app/tunnels.yml

USER crafty
ENV HOME=/home/crafty

EXPOSE 8443
ENTRYPOINT ["/entrypoint.sh"]