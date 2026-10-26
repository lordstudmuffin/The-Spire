# The Spire dedicated floor server image.
#
# Build the Linux server first (tools/server/export_server.ps1 -Platform linux,
# or Project > Export > "Linux Dedicated Server" in the editor), which writes
# build/linux-server/. Then, from the repository root:
#   docker build -f tools/server/Dockerfile -t the-spire-server .
#   docker run -d --name spire-floor1 --restart unless-stopped \
#     -p 4433:4433/udp -v spire-data:/data \
#     -e SPIRE_NAME="Town of First Light" the-spire-server
# or: docker compose -f tools/server/compose.yaml up -d
FROM debian:bookworm-slim

# Godot's headless runtime needs only a few shared libraries.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --system --create-home --home-dir /data --shell /usr/sbin/nologin spire

COPY build/linux-server/ /opt/the-spire/
COPY tools/server/run_server.sh /opt/the-spire/run_server.sh
RUN chmod +x /opt/the-spire/run_server.sh /opt/the-spire/the-spire-server.x86_64 \
	&& chown -R spire:spire /data

ENV SPIRE_BIN=/opt/the-spire/the-spire-server.x86_64 \
	SPIRE_DATA=/data \
	SPIRE_PORT=4433 \
	SPIRE_FLOOR=1 \
	SPIRE_CAPACITY=30

USER spire
VOLUME ["/data"]
EXPOSE 4433/udp

# Asks the server for its status (same query the game's realm list uses).
HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
	CMD /opt/the-spire/the-spire-server.x86_64 --headless -- --query 127.0.0.1 --port "$SPIRE_PORT" > /dev/null || exit 1

STOPSIGNAL SIGINT
ENTRYPOINT ["/opt/the-spire/run_server.sh"]
