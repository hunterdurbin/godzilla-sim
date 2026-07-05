# scripts/server/ — dedicated headless server

Runs full matches server-side so clients can't cheat and can reconnect.
Entry scene: `scenes/server/ServerMain.tscn` →

```
ServerMain            (server_main.gd — boot, CLI flags: --port=N --no-stats)
└── ConnectionManager (connection_manager.gd — WebSocket accept, HELLO/WELCOME,
    │                  room codes, seat assignment, version gate)
    └── GameRoom      (game_room.gd — one per match: owns a GameSession +
        │              HeadlessBoard, relays SceneMultiplayer RPC frames)
        ├── HeadlessBoard    (headless_board.gd — server-side implementation of
        │                     the `_board` duck-typed contract; no UI)
        └── RoomVirtualPeer  (room_virtual_peer.gd — per-client virtual
                              MultiplayerPeer inside the room)
```

Clients connect via `GameServerPeer` (`scripts/net/`): text WebSocket frames
carry the JSON control plane, binary frames carry SceneMultiplayer RPCs.

## Run & test

```bash
# Local run:
<godot> --headless --path . scenes/server/ServerMain.tscn -- --port=12091 --no-stats

# Integration harness (server + paired headless clients, DESYNC grep):
./tests/harness/run_harness.sh 3 <godot>
```

Deployment (systemd, ports 12101 stable / 12111 unstable, versioned
side-by-side): see [deploy/server/README.md](../../deploy/server/README.md).

## Contract notes

- `headless_board.gd` is one of the THREE `_board` implementations (with
  game_board.gd and the harness stub) — RPC-surface changes must hit all
  three (see `scripts/session/README.md`).
- The server validates actions via the pure `RulesEngine` before applying —
  never trust client-sent actions.
