# Dedicated servers

The Spire runs multiplayer **only on dedicated servers**. A player's game can't host. The Host button is gone, and `Net.host()` refuses unless the process was started with `--server` and runs headless (or is a `dedicated_server` export). Solo play is fully offline: no socket is opened, so nobody can join a solo game.

- **One server = one floor instance.** It holds up to 30 climbers (`Net.MAX_PLAYERS`; lower it with `--capacity N`). If you need more room, run more instances, each on its own port.
- **Play Online** in the main menu lists the realms from `config/servers.json` (shipped with the game). Players can add entries, or replace the list, in `user://servers.json`. Each row asks its server for status without joining: online/offline, climbers n/30, floor, ping and version.
- **Versions must match exactly** (`Net.GAME_VERSION` in `autoload/net.gd`). The server greets every connection with its version, and the client refuses a different build. The server also refuses a joiner on another build. Either way the player sees a clear "Version mismatch ... update" message. Bump `GAME_VERSION` with every release whose server and client must change together.
- Default port: **UDP 4433**.

## 1. Test on your own PC (Windows)

From the project folder:

```
tools\server\run_server.bat
```

That starts a headless Floor 1 server on UDP 4433. If it stops, it restarts after 5 s, backing off up to 60 s while it keeps crashing. Ctrl+C stops it for good.

- It uses `build\windows-server\the-spire-server.console.exe` if you exported one. Otherwise it runs Godot 4.3 (`C:\Godot\Godot_v4.3-stable_win64_console.exe`, or `$env:GODOT`) on the project source.
- Data lives in `%LOCALAPPDATA%\TheSpireServer\`. That covers character records (`Godot\app_userdata\Anime Life RPG\server_db\`), the realm world DB (`realm_db\`), Godot's log (`logs\godot.log`) and this script's console logs (`logs\server-<port>-<time>.log`, kept 14 days).
- Options: `-Port 4434 -Name "Test Realm II" -Floor 1 -Capacity 30 -DataDir D:\SpireData2 -Report -NoRestart`. When you run two servers at once, give each its own `-Port` **and** its own `-DataDir`. Two processes must never share one data folder: records and the realm DB have a single writer (docs/REALM_DB.md).

Then start the game. **Play Online** shows "Local Test Realm (This PC)" from `config/servers.json`.

- Friends on your LAN or the internet need your address in their `servers.json` (see section 4).
- For players outside your PC, allow the port through Windows Firewall (an admin PowerShell; this is a system setting, so run it yourself):
  `New-NetFirewallRule -DisplayName "The Spire server" -Direction Inbound -Protocol UDP -LocalPort 4433 -Action Allow`
- For internet players, also forward UDP 4433 on your router to this PC.

Health check from any shell (exit code 0 means online, 2 means offline):

```
godot --headless --path . -- --query 127.0.0.1 --port 4433
STATUS {"capacity":30,"compatible":true,"floor":1,"name":"Floor 1","online":true,"ping_ms":7,"players":2,...}
```

Bots for a soak test: `godot --headless --path . -- --join 127.0.0.1 --port 4433 --name BotA --bot --report`.

## 2. Build the server

The `export_presets.cfg` presets are:

- **Linux Dedicated Server**: writes `build/linux-server/the-spire-server.x86_64`.
- **Windows Dedicated Server**: writes `build/windows-server/the-spire-server.exe`, plus a `.console.exe`.
- **Windows Client**: the game for players. `config/*.json` is included in every preset.

Setup and export:

1. Install the Godot 4.3 export templates once: in the editor, **Editor > Manage Export Templates > Download and Install**.
2. Run `powershell -ExecutionPolicy Bypass -File tools\server\export_server.ps1 -Platform linux` (or `windows`, or `both`). You can also use **Project > Export** in the editor.

The server presets keep every resource. The server needs real collision meshes, so don't switch them to "Strip Visuals" without testing.

## 3. Run it on a cheap cloud VM (Linux)

A Floor 1 server idles at about 0.6 GB RAM with 2 bots, so a 2 vCPU / 2-4 GB VM fits one or two instances. Open **UDP 4433** (plus 4434 and up if you run more instances) in the provider's firewall.

**Option A: systemd** (simplest on a plain Ubuntu/Debian VM)

```
sudo useradd --system --home /var/lib/the-spire --shell /usr/sbin/nologin spire
sudo mkdir -p /opt/the-spire /var/lib/the-spire /etc/the-spire && sudo chown spire:spire /var/lib/the-spire
# copy build/linux-server/* and tools/server/run_server.sh to /opt/the-spire/ (scp), then:
sudo chmod +x /opt/the-spire/run_server.sh /opt/the-spire/the-spire-server.x86_64
sudo cp the-spire-server@.service /etc/systemd/system/
printf 'SPIRE_PORT=4433\nSPIRE_FLOOR=1\nSPIRE_NAME=Town of First Light I\n' | sudo tee /etc/the-spire/floor1.env
sudo systemctl daemon-reload && sudo systemctl enable --now the-spire-server@floor1
journalctl -u the-spire-server@floor1 -f        # logs
```

- `Restart=always` restarts it on a crash and after a reboot.
- Each instance keeps its data in `/var/lib/the-spire/<instance>/`. A second instance needs its own env file with another port: `floor1b.env` with `SPIRE_PORT=4434`, then `enable --now the-spire-server@floor1b`.

**Option B: Docker** (after exporting the Linux server, from the repo root)

```
docker compose -f tools/server/compose.yaml up -d --build
docker compose -f tools/server/compose.yaml logs -f
```

- `tools/server/Dockerfile` runs as a non-root user and keeps data in the `/data` volume.
- It restarts unless stopped and runs a health check with the same status query the game uses. Logs rotate at 20 MB × 5.
- The compose file runs two Floor 1 instances (UDP 4433 and 4434), each with its own volume.

Settings for both options are environment variables read by `tools/server/run_server.sh`:

| Variable | Default | Meaning |
|---|---|---|
| `SPIRE_PORT` | 4433 | UDP port |
| `SPIRE_FLOOR` | 1 | floor this instance runs |
| `SPIRE_NAME` | Floor N | name shown in the realm list |
| `SPIRE_CAPACITY` | 30 | max climbers (1-30) |
| `SPIRE_REALM` | server | realm id of the world DB |
| `SPIRE_DATA` | /var/lib/the-spire | persistent data dir |
| `SPIRE_REPORT` | 0 | 1 = log players, mobs and memory every few seconds |

Records are saved every 60 s and when the server shuts down cleanly. Realm DB claims are written to disk immediately. Back up the data dir (or the Docker volume) daily.

### Hosting options (Kyle's decision; nothing has been signed up for)

| Provider | Plan that fits one or two Floor 1 instances | Rough cost / month |
|---|---|---|
| Hetzner Cloud | CX22 / CPX21 (2 vCPU, 4 GB), EU or US | about $5-9 |
| DigitalOcean | Basic Droplet 2 vCPU / 2-4 GB | about $18-24 |
| Vultr or Linode (Akamai) | Shared 2 vCPU / 4 GB | about $20-24 |

Prices are approximate as of 2026; check the provider's site. Pick a region near your players: ping is shown in the realm list. Any of them works with Option A or B.

## 4. Put the server in the realm list

Edit `config/servers.json` before you build the client:

```json
{ "version": 1, "servers": [
  { "id": "eu-floor1-a", "name": "Town of First Light I", "region": "EU West",
    "address": "play.example.com", "port": 4433, "floor": 1 }
] }
```

- `address` can be an IP or a DNS name. Keep `id` stable: the menu remembers the last realm by id.
- The shipped file lists only "Local Test Realm" (127.0.0.1). Replace it with the official address once you have one.
- Players and testers can add their own entries without rebuilding by writing the same format to `user://servers.json`, which is `%APPDATA%\Godot\app_userdata\Anime Life RPG\servers.json` on Windows. Add `"replace": true` to hide the shipped list, or use the `--servers <file>` flag.

## 5. Command-line reference

Server flags go after `--`; add `--headless` before it.

| Flag | Where | Meaning |
|---|---|---|
| `--server` | server | run as a dedicated floor server (refused without `--headless`) |
| `--port N` | both | UDP port (default 4433) |
| `--floor N` | server | floor to run |
| `--server-name "X"` | server | name reported to the realm list |
| `--capacity N` | server | max climbers, 1-30 |
| `--realm id` | server | realm world DB id |
| `--report` | both | periodic health line |
| `--query ADDR` | tool | print a server's status JSON and exit (0 online / 2 offline) |
| `--join ADDR --name X [--bot]` | client | test hook: skip the menu and join directly |
| `--servers FILE` | client | use another realm list override file |
| `--net-version X` | both | test hook: pretend to be build X (exercises the version refusal) |
