# Dedicated Game Server — Deploy

The dedicated server replaces the relay for online play: it runs the
authoritative game logic headless, validates every action, and lets either
player reconnect mid-match (seat tokens, 90s claim-win grace).

## Ports

| Port  | What |
|-------|------|
| 12091 | Game traffic (WebSocket: JSON control plane + binary RPC frames) |
| 12092 | HTTP — `/` status text (Discord-bot compatible), `/rooms?mode=X` public listing JSON |

## Build & run

```bash
# 1. Export the server binary (requires Godot export templates)
godot --headless --export-release "Linux Server" build/server/godzilla_tcg_server.x86_64

# 2. Build the image (from the repo root)
docker build -f deploy/server/Dockerfile -t godzilla-tcg-server .

# 3. Run
docker compose -f deploy/server/docker-compose.yml up -d
```

Dev run without Docker:

```bash
godot --headless --path . scenes/server/ServerMain.tscn -- --port=12091
# optional: --grace=N to shorten the claim-win window for testing
```

## Verify

```bash
curl http://localhost:12092/            # "Godzilla TCG server running. N active rooms."
curl http://localhost:12092/rooms       # []
./scenes/server/tests/run_harness.sh 3  # full random games over the wire
```

## Cutover plan (M5)

1. Soak the server on 12091/12092 alongside the relay (12090).
2. Ship a client release whose online play targets the server
   (`NetworkManager.server_host/server_port`); old clients keep using the
   relay and are version-gated at HELLO.
3. Retarget the Discord bot: `RELAY_SERVER_URL=http://<host>:12092`.
4. Once relay traffic dies off, retire the relay service and delete the
   legacy paths (`relay_multiplayer_peer.gd`, `host_online`/`join_online`/
   relay `attempt_reconnect` in NetworkManager).

Game state is in-memory: a server restart drops live matches (clients see
the disconnect overlay and can claim/rematch). Restart during low-traffic
windows; persistence via GameSerializer snapshots is a possible follow-up.
