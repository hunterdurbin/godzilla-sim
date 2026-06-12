# Dedicated Game Server — Deploy & Channels

The dedicated server replaces the relay for online play: it runs the
authoritative game logic headless, validates every action, and lets either
player reconnect mid-match (seat tokens, 90s claim-win grace).

One server runs **per release channel** — the HELLO handshake version-gates
clients, so stable and unstable builds each talk to their own server running
their channel's latest version. Clients pick their channel's port
automatically from their own version string (`NetworkManager.server_port`).

## Ports

| Channel  | WebSocket | HTTP status + `/rooms` | Notes |
|----------|-----------|------------------------|-------|
| stable   | 12101     | 12102                  | deploys need manual approval |
| unstable | 12111     | 12112                  | deploys automatically |
| (relay)  | 12090 prod / 12091 dev | —         | untouched until relay retirement |

Inside the container the server always listens on 12091/12092; only the host
port mappings differ per channel.

## Auto-deploy pipeline (`.github/workflows/release.yml`)

Pushing a `v*` tag (e.g. `v0.1.13-unstable.1`, `v0.1.13-release`):
1. `export-server` builds the "Linux Server" preset (one preset for both
   channels — the channel is baked into the version string) and attaches
   `godzilla_tcg_server-linux.zip` to the GitHub release.
2. `build-server-image` pushes `ghcr.io/<owner>/godzilla-tcg-server` tagged
   with the exact ref (`:v0.1.13-unstable.1`) plus the channel alias
   (`:unstable` / `:stable`).
3. `deploy-server-unstable` (unstable tags, automatic) or
   `deploy-server-stable` (stable tags, **waits for approval** via the
   `production` GitHub environment) SSHes to the host, pins the exact image
   tag in `.env`, and runs `docker compose pull && up -d`, then curls the
   status endpoint as a smoke check.

**Rollback:** re-run an older tag's deploy job from the Actions UI — `.env`
pins the exact image tag, so the previous version comes back as-is.

## One-time setup

GitHub repo settings:
- Secrets: `DEPLOY_SSH_HOST`, `DEPLOY_SSH_USER`, `DEPLOY_SSH_KEY` (private
  key for a deploy user on the host).
- Environment `production` with yourself as a required reviewer (gates the
  stable deploy job).
- GHCR package visibility: after the first push, set the
  `godzilla-tcg-server` package to public (Packages → settings), or run
  `docker login ghcr.io` on the host with a read-only PAT.

Host provisioning:
```bash
sudo mkdir -p /opt/godzilla-game-server/{stable,unstable}
# from this repo:
scp deploy/server/docker-compose.stable.yml   host:/opt/godzilla-game-server/stable/docker-compose.yml
scp deploy/server/docker-compose.unstable.yml host:/opt/godzilla-game-server/unstable/docker-compose.yml
```

Discord status bot (optional): point `RELAY_SERVER_URL` at
`http://<host>:12102` (stable) or `:12112` (unstable) — the status text keeps
the "N active rooms" phrasing the bot regexes, now with the running version:
`Godzilla TCG server v0.1.13-release running. 3 active rooms.`

## Local dev & testing

```bash
# run a server from the project (no export needed)
godot --headless --path . scenes/server/ServerMain.tscn -- --port=12091 --no-stats
# optional flags: --grace=N (shorten claim-win window), --port=N

# full random games over the wire (boots its own server on $PORT, default 12091)
./scenes/server/tests/run_harness.sh 3
# concurrency drill: N games at once in one server process
./scenes/server/tests/run_concurrency.sh 5

# build the image locally (mirrors CI)
godot --headless --path . --export-release "Linux Server" build/server/godzilla_tcg_server.x86_64
docker build -f deploy/server/Dockerfile -t godzilla-tcg-server .

# point a locally-run client at any server
<client> -- --server-host=127.0.0.1 --server-port=12111
```

## Verify a deploy

```bash
curl http://godzillatcg.com:12112/    # unstable: "Godzilla TCG server vX.Y.Z-unstable.N running. ..."
curl http://godzillatcg.com:12102/    # stable
curl "http://godzillatcg.com:12112/rooms?mode=rumble_west"
```

## Cutover plan (relay retirement)

1. Soak both channel servers alongside the relay (12090/12091).
2. Ship client releases on both channels (they target 12101/12111).
3. Retarget the Discord bot.
4. Once relay traffic dies off, retire the relay service and delete the
   legacy paths (`relay_multiplayer_peer.gd`, `host_online`/`join_online`/
   relay `attempt_reconnect` in NetworkManager).

Game state is in-memory: a server restart drops live matches on that channel
(clients see the disconnect overlay). Deploy unstable freely; time stable
deploys for low traffic. Persistence via GameSerializer snapshots is a
possible follow-up.
