FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl gnupg apt-transport-https ca-certificates unzip \
    && curl -fsSL https://packagecloud.io/pufferpanel/pufferpanel/gpgkey | gpg --dearmor -o /etc/apt/keyrings/pufferpanel.gpg \
    && echo "X-Repolib-Name: PufferPanel\nTypes: deb\nURIs: https://packagecloud.io/pufferpanel/pufferpanel/any/\nSuites: any\nComponents: main\nSigned-By: /etc/apt/keyrings/pufferpanel.gpg" \
       > /etc/apt/sources.list.d/pufferpanel.sources \
    && apt-get update && apt-get install -y pufferpanel \
    && rm -rf /var/lib/apt/lists/*

# Install ngrok
RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok

# HF Spaces containers run as a non-root user with a writable /data or $HOME
RUN mkdir -p /etc/pufferpanel /var/lib/pufferpanel \
    && chmod -R 777 /etc/pufferpanel /var/lib/pufferpanel

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]