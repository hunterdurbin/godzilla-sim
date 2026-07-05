# scripts/session/ — session glue (engine ↔ board ↔ network)

Owns everything between the pure engine (`scripts/core/`) and a concrete
board: session lifecycle, multiplayer state sync, and effect-UI routing.

## Files

| File | Role |
|---|---|
| `game_session.gd` | `GameSession` — owns the TurnManager/engine graph for one match, exposes `events` (GameEvents bus); the node a board parents to drive a game |
| `multiplayer_sync.gd` | **The sole `@rpc` surface (all 49 RPCs).** Serializes state/actions between host and clients; calls into the board via the duck-typed `_board` contract |
| `effect_ui_router.gd` | Routes effect-driven UI requests (choices, zone targets, highlights) between engine PlayerInput signals and board UI / RPCs |
| `board_module.gd` | `BoardModule` base — helpers for board submodules to find the session/board via the named "GameBoard" subtree |
| `seat_container.gd` | Seat/player-slot mapping helper for board layouts |
| `session_config.gd` / `net_context.gd` | Per-match configuration and network-context plumbing |
| `state_codec.gd` | State encode/decode helpers used by sync |
| `bound_label.gd` / `session_bound_label.gd` | Label bindings that track session state values |

## The `_board` duck-typed contract (critical)

`multiplayer_sync.gd` (and other session modules) call `_board._rpc_*`,
`_board._on_*`, and read `_board._x` fields. THREE implementations must stay
in lockstep:

1. `scenes/board/game_board.gd` — the real UI board
2. `tests/harness/stub_client_board.gd` — headless harness client
3. `scripts/server/headless_board.gd` — dedicated-server board

**Any change to an RPC-facing board method must hit all three.** Unit tests
don't exercise this contract; `tests/harness/run_harness.sh` does — run it
after touching any of these surfaces. Multiplayer battle_zones are per-card
(`_compute_playable_data()` sends a Dictionary card-id → zones, not a flat
array).

## Conventions

- Signals on the bus/forwarding shims carry
  `@warning_ignore("unused_signal")`; polymorphic `_board.*` fields need
  `@warning_ignore("unused_private_class_variable")` per class.
- Scene contract (validated by `scripts/tools/check_designer_contract.gd`):
  a board scene's root is named `GameBoard` with a `GameSession` child
  containing `MultiplayerSync` (+ `EffectUIRouter` recommended).
