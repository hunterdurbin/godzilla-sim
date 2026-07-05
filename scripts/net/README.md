# scripts/net/ — transport layer

Connection plumbing only — no game logic (that's `session/` and `core/`).

| File | Role |
|---|---|
| `network_manager.gd` | **Autoload `NetworkManager`** — the connection lifecycle brain: LAN (ENet) via `host_game()/join_game()`, online relay via `host_online()/join_online()/host_public()`, dedicated server via `connect_to_server()/create_room()/join_room()`, plus reconnect (`resume_online_session()`), version gating, keepalive, seat signals (`game_starting`, `server_seated`, …), and the `Mode` enum (SOLO/SOLO_BOT/HOST/CLIENT/ONLINE_*). Loads `res://scenes/board/GameBoard.tscn` when a game starts. CLI: `--server-host=`, `--server-port=`. `USE_DEDICATED_SERVER` master switch. |
| `game_server_peer.gd` | `GameServerPeer` (MultiplayerPeerExtension) — client bridge to the dedicated server: text WS frames = JSON control plane, binary frames = SceneMultiplayer RPCs |
| `relay_multiplayer_peer.gd` | `RelayMultiplayerPeer` (MultiplayerPeerExtension) — 2-player WebSocket relay transport (host id 1, client id 2) |
| `rpc_logger.gd` | **Autoload `RpcLogger`** — debug per-RPC send/receive byte tallies (`log_send`/`log_receive`/`print_summary`) |
| `chat_filter.gd` | `ChatFilter.filter(text)` — static profanity mask with leetspeak/separator evasion handling; used for public-room player names |

Endpoints: relay `ws://godzillatcg.com:12090/<room>`; dedicated server
`ws://<host>:12101` (stable) / `:12111` (unstable); public-room list over
HTTP on the same hosts. The actual gameplay RPCs live in
`scripts/session/multiplayer_sync.gd` — this layer only moves bytes.
