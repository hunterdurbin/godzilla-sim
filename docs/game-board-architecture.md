# GameBoard architecture & designer guide

The game board is decomposed into a **session layer** (game logic ownership +
multiplayer), **modules** (one concern each, visible as nodes in the scene
tree), and **overlay scenes** (each prompt/viewer is its own editable .tscn).
`game_board.gd` is the thin coordinator that wires them in `_ready()`.

## Scene-tree contract (multiplayer)

Every GameBoard scene's **root node must be named `GameBoard`** and contain:

```
GameBoard
└── GameSession              # owns TurnManager / BotPlayer / ReplayRecorder + client caches
    ├── MultiplayerSync      # ALL @rpc methods live here (stable NodePath on both peers)
    └── EffectUIRouter       # effect-prompt dispatch (recommended)
```

RPCs route by NodePath, so host and client may load *different* .tscn files
(desktop vs mobile variant) as long as this named subtree matches. Validate
any board scene with:

```
godot --headless --quit --script scripts/tools/check_designer_contract.gd -- --all
```

## Layers

| Layer | Path | Contents |
|---|---|---|
| Session | `scripts/session/` | `GameSession`, `MultiplayerSync`, `StateCodec` (wire format — keep byte-identical), `EffectUIRouter`, `BoardModule` (tree-walk discovery), `SeatContainer`, `BoundLabel` / `SessionBoundLabel` |
| Modules | `scenes/board/modules/` | `BoardSfx`, `LogChat`, `TurnTrackerModule`, `FirstPlayerUI`, `EndGameController`, `ReconnectController`, `HandController`, `SelectionController`, `MobileLayout` |
| Overlays | `scenes/board/overlays/` | DeckSearch, DeckArrange, CardSelect, DiscardView / MonsterDeckView / ZoneStackView (shared `card_grid_viewer.gd`), CardZoom, `overlay_grid_util.gd` |
| HUD components | `scenes/board/hud/` | Drop-in self-binding widgets: RageDisplay, ThreatDisplay, DeckCountLabel, DiscardCountLabel, PhaseLabel, TurnNumberLabel, HandSortButton, HUDBar |

## How binding works

- `GameSession.session_started` fires on host start **and every rematch**
  (and on a client's first received state). Modules subscribe in `_ready()`
  and (re)bind their signals there with idempotent connects — never wire a
  module from outside.
- `GameSession.client_state_applied` fires on client peers after every state
  broadcast. Client-side `PlayerState` objects are rebuilt per receive, so
  anything displaying player state rebinds/refreshes on this signal
  (`BoundLabel` already does).
- `BoardModule.find_session(node)` / `find_router(node)` let any node you
  drop under the board locate the session layer without wiring.

## Adding a HUD widget (designer workflow)

1. Instance e.g. `scenes/board/hud/RageDisplay.tscn` anywhere under the
   board root and set its `player_id` — or place it inside a
   `SeatContainer` (role LOCAL / OPPONENT / PLAYER_N) and it resolves the
   player automatically, including spectator side-swaps via `role_changed`.
2. That's it: `BoundLabel` handles session lookup, signal subscription,
   host-vs-client timing, and teardown. A new widget subclass only
   overrides `_refresh(session, player)`.

## Adding/replacing an effect-prompt overlay

Overlays register themselves with the router in `game_board._ready()`
**before** `start_host_session()`:

```gdscript
_router.register_handler("deck_search", deck_search_overlay.show_prompt)
```

The handler receives the request args plus a **resolve callback as the last
argument** — call it with the player's pick and the router does the
host-vs-client RPC dance internally. Keys without a registered handler keep
whatever legacy path still serves them, so migration is incremental. See the
handler signature table in `scripts/session/effect_ui_router.gd`.

## Known transitional state

- `game_board.gd` keeps forwarding properties + shims as the public surface
  modules reach through (`_board.<old name>`); they shrink as ownership
  finishes migrating.
- `SelectionController`'s five inline prompts (hand discard, hand card
  select, zone target, strategy target, choice) still use their legacy RPC
  routing rather than router handlers.
- `MobileLayout` restyles the desktop scene at runtime; the end state is a
  dedicated `MobileGameBoard.tscn` variant (the RPC contract above already
  permits it).
- Backlog from the old `restructure` branch (readable via
  `git show restructure:<path>`): MockStatePreview editor preview (needs a
  scene-driven PlayerBoard first), HandSlot, GameBoardTemplate /
  PlayerBoardTemplate, board-variant picker.
