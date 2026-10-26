#!/bin/sh
# The Spire: start one dedicated floor server (Linux). Used by the systemd unit
# and the Docker image; run it by hand the same way. Restarts are the job of
# systemd (Restart=always) or Docker (restart: unless-stopped).
#
# Settings come from the environment (defaults in brackets):
#   SPIRE_BIN       server binary         [/opt/the-spire/the-spire-server.x86_64]
#   SPIRE_PROJECT   run from source instead: path to the project folder, with
#                   SPIRE_BIN pointing at a Godot 4.3 Linux binary
#   SPIRE_PORT      UDP port              [4433]
#   SPIRE_FLOOR     floor number          [1]
#   SPIRE_NAME      name in the realm list ["Floor 1"]
#   SPIRE_REALM     realm id (servers sharing a data dir and realm id share one world DB) [server]
#   SPIRE_CAPACITY  max players, 1..30    [30]
#   SPIRE_DATA      persistent data dir (records, realm DB, logs) [/var/lib/the-spire]
#   SPIRE_REPORT    1 = log a health line (players, mobs, memory) every few seconds [0]
set -eu

SPIRE_BIN="${SPIRE_BIN:-/opt/the-spire/the-spire-server.x86_64}"
SPIRE_PORT="${SPIRE_PORT:-4433}"
SPIRE_FLOOR="${SPIRE_FLOOR:-1}"
SPIRE_NAME="${SPIRE_NAME:-Floor ${SPIRE_FLOOR}}"
SPIRE_REALM="${SPIRE_REALM:-server}"
SPIRE_CAPACITY="${SPIRE_CAPACITY:-30}"
SPIRE_DATA="${SPIRE_DATA:-/var/lib/the-spire}"

mkdir -p "$SPIRE_DATA"
# Godot keeps user:// under $XDG_DATA_HOME/godot/app_userdata/<project name>:
# character records (server_db/), the realm world DB (realm_db/) and
# logs/godot.log all land in the persistent data dir.
export XDG_DATA_HOME="$SPIRE_DATA"

set -- --headless
if [ -n "${SPIRE_PROJECT:-}" ]; then
	set -- "$@" --path "$SPIRE_PROJECT"
fi
set -- "$@" -- --server --port "$SPIRE_PORT" --floor "$SPIRE_FLOOR" --realm "$SPIRE_REALM" \
	--capacity "$SPIRE_CAPACITY" --server-name "$SPIRE_NAME"
if [ "${SPIRE_REPORT:-0}" = "1" ]; then
	set -- "$@" --report  # periodic players / mobs / memory / orphans line
fi

echo "[run_server] $(date -u +%FT%TZ) starting '$SPIRE_NAME' floor $SPIRE_FLOOR on udp $SPIRE_PORT, data $SPIRE_DATA"
exec "$SPIRE_BIN" "$@"
