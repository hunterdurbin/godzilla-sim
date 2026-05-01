# Building a new GameBoard scene

This is the canonical reference for designers / developers building a new
GameBoard scene (mobile, desktop, VR, themed variants, etc.). It covers the
cross-scene multiplayer contract, the module composition pattern, and how
to add new variants of overlays / HUD / action panels.

## Quick start (3 steps)

1. **File → New Inherited Scene → `scenes/board/GameBoardTemplate.tscn`.**
   You get a fully populated working board (both seats with PlayerBoard
   + HUD, ActionPanel, LogPanel, TopBar with TurnNumber/Phase/Menu).
2. **Save as `scenes/board/MyGameBoard.tscn`.** The root node MUST stay
   named `GameBoard` (multiplayer contract — see below).
3. **Edit visuals.** Drag inherited children to reposition, change
   colors / fonts / sizes, swap HUD primitives. Do NOT remove
   `GameSession`, `MultiplayerSync`, `EffectUIRouter`, or the seats.

That's it. Run the scene via the 🧪 button in the main menu — any
`*GameBoard.tscn` file dropped in `scenes/board/` (except the template,
base, and legacy production scene) is auto-discovered and added to the
picker.

### Going off-template

If you want a more minimal starting point — say, a fresh layout that
doesn't share the template's BoardLayoutSlot structure — inherit from
`scenes/board/GameBoardBase.tscn` instead. You get just the engine
subtree (GameSession + MultiplayerSync + EffectUIRouter) and an empty
`BoardLayoutSlot` with two seat containers. You'll need to drop in
your own PlayerBoard, HUD primitives, ActionPanel, etc. — all of them
self-bind via tree-walk so no controller wiring is needed.

## Anatomy of GameBoardTemplate.tscn

The template ships with this structure (children of the inherited base
in **bold**, new in the template italicized):

```
GameBoard                            (Control, game_board_template.gd)
├── **GameSession**                  (engine; do not remove)
│   ├── **MultiplayerSync**
│   └── **EffectUIRouter**
├── **DefaultOverlayPack**           (7 modal overlays — auto-register)
├── **BoardLayoutSlot**
│   ├── **OpponentSeat** (role=OPPONENT)
│   │   └── *OpponentVBox*
│   │       ├── *HUDBar* (RageDisplay, ThreatDisplay, DeckCountLabel,
│   │       │              DiscardCountLabel)
│   │       └── *PlayerBoard* (auto_bind=true, is_mirrored=true)
│   └── **LocalSeat** (role=LOCAL)
│       └── *LocalVBox*
│           ├── *PlayerBoard* (auto_bind=true)
│           └── *HUDBar* (RageDisplay, ThreatDisplay, DeckCountLabel,
│                          DiscardCountLabel, HandSortButton)
├── *TopBar* (TurnNumberLabel, PhaseLabel, MenuButton)
├── *ActionPanel* (auto-detected by GameBoardBase via signal probe)
└── *LogPanel*
```

Each HUD primitive resolves its `player_id` from the surrounding
`SeatContainer` automatically — no per-module configuration. Modals
(`DefaultOverlayPack`) self-register with the `EffectUIRouter` on
`_ready`. The script (`game_board_template.gd`) only wires the
Return-to-Menu button; everything else is inherited.

## Cross-scene multiplayer contract

If your new GameBoard scene is going to play multiplayer against another
GameBoard scene (mobile vs desktop, themed variants, etc.), the network
layer needs to find the same node at the same path on both peers. This is
enforced by a single rule:

**The root node of your scene must be named exactly `GameBoard`.**

The `.tscn` file name can be anything (`MobileGameBoard.tscn`,
`NeonGameBoard.tscn`, etc.). What matters is the root node name in the
saved scene.

The required subtree below the root:

```
GameBoard                                   (Control or Node)
├── GameSession                             (Node + game_session.gd)
│   ├── MultiplayerSync                     (Node + multiplayer_sync.gd)
│   └── EffectUIRouter                      (Node + effect_ui_router.gd)
└── ... your visual layout, modules, etc.
```

A runtime assertion in `GameSession._ready()` will `push_error` if your
root isn't named `GameBoard`, so this is hard to mess up silently.

`GameBoardBase.tscn` already has this subtree pre-built. If you start from
it, you don't have to think about any of this.

## Module composition

A "module" is anything you drop into the GameBoard scene tree as a
descendant of the root — overlay scenes, HUD components, custom action
panels, etc. The whole point of the architecture is that modules
**self-bind** in their `_ready()` rather than being explicitly wired by
the root scene's controller script.

### Tree-walk lookup

Every module uses the static helpers in `scripts/session/board_module.gd`:

```gdscript
func _ready() -> void:
    var session := BoardModule.find_session(self)
    var router := BoardModule.find_router(self)
    var sync := BoardModule.find_multiplayer_sync(self)
    # ...
```

These walk up to the `GameBoard` root via `find_parent("GameBoard")`,
then down to the named child. They return `null` and emit a warning if the
contract is violated, so failures are easy to debug.

### Self-registering overlays

The 7 standard modal overlays (DeckSearch, DeckArrange, CardSelect,
DiscardView, MonsterDeckView, ZoneStackView, CardZoom) self-register
with the `EffectUIRouter` on `_ready` using their `prompt_key` export.

This means: drop an overlay scene anywhere in your GameBoard tree → it
auto-routes the matching effect prompt. No code change needed.

To override the default with a custom variant:

1. Make a new scene that extends or replaces the default overlay.
2. Set its `prompt_key` to the same key (e.g. `"deck_search"`).
3. Place it in your scene tree alongside or instead of the default.
4. Auto-registration runs in scene-tree order — the last-registered
   handler wins.

The cleanest approach for a custom variant is:

```
GameBoard
├── GameSession ...
└── MyCustomOverlays
    └── FancyDeckSearchOverlay   (custom .tscn, prompt_key = "deck_search",
                                   inherits or composes the default's API)
```

If you want absolute control, set `auto_register = false` on the default
overlay's instance and explicitly call `router.register_handler()` from
your scene's script.

### Seat containers — assign players to sides without per-module config

A `SeatContainer` (`scenes/board/SeatContainer.tscn`) is a Control with
a `role` property (`LOCAL` / `OPPONENT` / `PLAYER_0` / `PLAYER_1`). Any
module dropped under it auto-resolves its `player_id` from the seat
instead of needing the inspector to be set per-module.

This is the canonical way to build a player-portable scene. The same
saved scene file works whether the local player is 0 (host) or 1
(client) — `LOCAL` resolves to `NetworkManager.local_player_id` at
scene-load.

`GameBoardBase.tscn` already includes two seat containers as
scaffolding:

```
GameBoard
├── GameSession ...
└── BoardLayoutSlot
    ├── OpponentSeat   (SeatContainer, role=OPPONENT, top half)
    └── LocalSeat      (SeatContainer, role=LOCAL,    bottom half)
```

Drop a `PlayerBoard.tscn` (with `auto_bind=true`) plus any HUD
primitives inside `LocalSeat` — they'll resolve to the local player's
id at runtime. Same for `OpponentSeat`. **Designer never sets
`player_id` per module.**

```
LocalSeat
├── PlayerBoard         (auto_bind=true; resolves via seat)
├── RageDisplay         (resolves via seat)
├── ThreatDisplay
└── DiscardCountLabel
```

If a module is *not* under any SeatContainer (e.g., a `LogPanel` or
a global `TurnNumberLabel` floating outside both seats), it falls back
to its own `@export player_id` — the seat lookup is opt-in by
placement.

#### Roles

| Role | Resolves to |
| --- | --- |
| `LOCAL` | `NetworkManager.local_player_id` |
| `OPPONENT` | `1 - NetworkManager.local_player_id` |
| `PLAYER_0` | `0` (always) — for spectator / replay scenes |
| `PLAYER_1` | `1` (always) |

`is_mirrored` on PlayerBoard remains independent — orientation is a
visual decision, not a seat decision. A scene can put `LOCAL` at the
top with mirroring on if the layout calls for it.

#### Modules that honor SeatContainer

PlayerBoard, RageDisplay, ThreatDisplay, DeckCountLabel, DiscardCountLabel.
Any other custom module can opt in by adding a single block to its
`_try_bind()`:

```gdscript
var seat := BoardModule.find_seat(self)
if seat:
    player_id = seat.get_player_id()
    seat.role_changed.connect(_on_seat_role_changed)
```

The `role_changed` signal is what makes runtime swap work — when the
seat's role flips, modules re-resolve and re-bind to the new player's
state.

#### Dynamic seat swap (spectator UIs)

`SeatContainer.set_role(role)` and `SeatContainer.swap()` change the
role at runtime and emit `role_changed(new_player_id)`. All modules
under that seat automatically rebind to the new player's
`PlayerState`.

Typical use: a spectator scene with two seats `LeftSeat` (role=PLAYER_0)
and `RightSeat` (role=PLAYER_1) plus a "Swap sides" button:

```gdscript
func _on_swap_pressed() -> void:
    $LeftSeat.swap()
    $RightSeat.swap()
```

After the press, all modules under both seats re-resolve and the
visible player on each side flips.

### Building a regular-play scene — step by step

For a normal play scene (not spectator) the pattern is the same shape
as the spectator tutorial below, just with `LOCAL`/`OPPONENT` seat
roles plus an action panel for the seated player.

**1. Create the scene from the base template.**

   - Right-click `scenes/board/GameBoardBase.tscn` in the FileSystem
     dock → `Open in New Scene` (or open it and `Scene → Save As…`).
   - Save as e.g. `scenes/board/MobileGameBoard.tscn` or
     `DesktopGameBoard.tscn`. Keep the root node named `GameBoard`.
   - Replace the script reference on the root with your own controller
     script (or `extends "res://scenes/board/game_board_base.gd"`).

**2. Configure the two seat containers.**

   The base template ships with `OpponentSeat` (top half, `role=OPPONENT`)
   and `LocalSeat` (bottom half, `role=LOCAL`). Resize/anchor them to
   match your visual layout. Rename them if you prefer (cosmetic only).

   You can put `LOCAL` at the top and `OPPONENT` at the bottom — the
   seat's `role` resolves to a player_id at runtime regardless of
   visual placement. Use `is_mirrored` on each PlayerBoard to flip
   orientation independently.

**3. Drop core modules into each seat.**

   Inside `LocalSeat`:

   - `scenes/board/PlayerBoard.tscn` — set `auto_bind = true`. Set
     `is_mirrored` based on whether this seat is at the top of the
     screen (mirrored) or bottom (not mirrored).
   - `scenes/managers/CardManager.tscn` — for the local player's hand.
     Set `PlayerBoard.hand_manager_path` to point at it.
   - HUD primitives as needed: `RageDisplay`, `ThreatDisplay`,
     `DeckCountLabel`, `DiscardCountLabel`. None need `player_id` —
     the seat resolves it.

   Repeat in `OpponentSeat`. The opponent's CardManager renders cards
   face-down by default (CardManager handles face-down based on hand
   visibility — game_board's `_update_hand_visibility` is the
   reference).

**4. Add global modules outside the seats.**

   These don't belong to a single player:

   - `scenes/board/hud/TurnTrackerView.tscn`
   - `scenes/board/hud/TurnNumberLabel.tscn`
   - `scenes/board/hud/PhaseLabel.tscn`
   - `scenes/board/hud/LogPanel.tscn`
   - `scenes/board/hud/EndGamePanel.tscn`
   - `scenes/board/hud/BoardSfx.tscn` — drop-in audio.

   `DefaultOverlayPack` is already inherited from the base, so the
   modal overlays (DeckSearch, CardSelect, DeckArrange, CardZoom,
   etc.) are wired automatically.

**5. Drop in the action panel.**

   Instance `scenes/board/hud/ActionPanel.tscn` into your scene
   (typically inside `LocalSeat` or near it). It ships with the 6
   action buttons (Play Battle / Play Strategy / Gain Rage / Play
   Monster / Invade / End Main) plus Cancel/Confirm and a prompt
   label.

   `GameBoardBase` auto-detects the ActionPanel descendant and creates
   a `SelectionModeController` that:

   - Listens for the panel's `action_pressed(action)` signal.
   - Validates turn ownership + queries the rules engine for playable
     hand indices.
   - Enters card selection mode on the active player's hand_manager.
   - For PLAY_BATTLE, follows up with zone selection (click-only).
   - Submits the chosen action via `session.submit_action(...)`.
   - Listens for `awaiting_player_action` to enable / disable buttons
     per turn and per the rules-engine valid set.

   **Custom action panels**: you can replace the default with any
   node that fulfills the contract (`signal action_pressed(action)`,
   `signal cancel_pressed`, `signal confirm_pressed`,
   `set_button_enabled(action, bool)`, `show_prompt(text)`,
   `hide_prompt()`). GameBoardBase finds the first descendant with the
   `action_pressed` signal — your custom panel just needs that.

   **Drag-to-zone is built in.** SelectionModeController also listens
   to each PlayerBoard's `hand_manager.hand_card_drag_started` /
   `_drag_ended` signals. On drag-start it queries the rules engine
   for valid drop targets (zones, strategy slots, rage zone, discard
   zone) and highlights them on the active PlayerBoard. On drag-end
   it submits the matching action based on which target the mouse
   is over. Click and drag both work; the click flow stays available
   for keyboard-only / accessibility paths.

   Snap-preview animation while dragging is **not** included — the
   default just highlights and submits. Designer can layer that on
   per-scene if they want (see `game_board.gd._update_snap_preview`
   for the reference implementation).

   **Pass-confirmation** is settings-gated. If
   `GameSettings.confirm_main_phase_pass` is on, pressing End Main
   shows a "End your turn?" prompt on the action panel; press Confirm
   to submit, Cancel to back out.

   **Auto-confirm overlays** for engine confirmation prompts (draw
   cards, discard strategies, etc.) are also settings-gated. If the
   relevant `GameSettings.auto_X` flag is on, the engine's
   `confirmation_requested` is auto-acknowledged. Otherwise the
   action panel shows a Confirm/Cancel prompt and the local player
   decides. Spectators and bot turns auto-confirm regardless (no UI
   to ask).

**6. Override the visual hooks in your controller.**

   `game_board_base.gd` exposes protected hooks. Override the ones
   you care about for visuals:

   ```gdscript
   extends "res://scenes/board/game_board_base.gd"

   @onready var _phase_label: Label = $HUD/PhaseLabel
   @onready var _turn_label: Label = $HUD/TurnNumberLabel

   func _on_phase_started(phase: CardEnums.GamePhase) -> void:
       # PhaseLabel auto-binds; this hook is for any *additional*
       # custom logic (e.g. play a phase-transition animation).
       _animate_phase_change(phase)

   func _on_turn_started(player_id: int) -> void:
       _flash_turn_indicator(player_id)
   ```

   You don't need to wire HUD primitives manually — they auto-bind.
   These hooks are only for custom visuals on top of that.

**7. Wire the launcher.**

   The existing main menu launches games via
   `NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")`.
   To launch your new scene, either:

   a. Edit `scenes/ui/main_menu.gd` to point at your scene file
      (replace the path in `_on_start_pressed`, `_on_solo_bot_pressed`,
      etc.).

   b. Add a parallel "Use new GameBoard" toggle behind a debug flag
      that switches the path. Lets the existing scene stay as a
      fallback during iteration.

   The mode flags (`SOLO`, `SOLO_BOT`, `HOST`, etc.) and deck
   selections still flow through `NetworkManager` and
   `DecklistManager` exactly as before — the new scene just consumes
   them via `GameBoardBase._ready`.

**8. Verify.**

   - F6 the scene with `NetworkManager.mode = Mode.SOLO_BOT` set in
     the scene's `_ready` for a quick standalone test (or set it from
     a launcher and use `change_scene`).
   - Open menu → press your launcher → game starts → bot takes its
     turn → you press End Main on your turn → next turn fires.
   - Trigger an effect that opens an overlay (e.g. a card with deck
     search) → confirm the overlay appears.
   - Online host+client: launch two peers, both loading your new
     scene. Confirm the seat resolution flips between host and client
     (LOCAL on host = pid 0; LOCAL on client = pid 1).

**9. Iterate on visuals.**

   With everything wired, you can spend your time on what actually
   matters: card animations, board art, themes, mobile gestures,
   layouts. The wiring stays put.

#### Regular-play scene template

A minimal controller script:

```gdscript
extends "res://scenes/board/game_board_base.gd"

# All wiring is automatic. The base script:
#   - Boots GameSession + bot + replay
#   - Connects effect-prompt routing through DefaultOverlayPack
#   - Auto-binds PlayerBoards via SeatContainers
#   - Auto-creates a SelectionModeController over the ActionPanel
#
# You only override the visual hooks for your custom UX.

func _on_phase_started(phase: CardEnums.GamePhase) -> void:
    # Custom animations, etc.
    pass

func _on_turn_started(player_id: int) -> void:
    # Flash a turn indicator, play a custom sound, etc.
    pass
```

That's the shell. With ActionPanel + DefaultOverlayPack + seat
containers all auto-wired, the controller script is purely visual
customization. The full play loop works without any selection-mode
code.

### Spectator network support

A peer can join a host as a spectator instead of as the second seated
player. Spectators receive the full state broadcast (both hands
visible) but their action submissions are rejected by the existing pid
validation, so no client-side enforcement is needed.

#### Joining as a spectator (LAN)

```gdscript
NetworkManager.join_as_spectator("192.168.x.y", NetworkManager.DEFAULT_PORT)
NetworkManager.change_scene("res://scenes/board/MySpectatorBoard.tscn")
```

`join_as_spectator()` mirrors `join_game()` but on connection sends a
`_rpc_register_as_spectator` RPC to the host. The host overrides the
peer's seat assignment in `peer_player_map` to
`NetworkManager.SPECTATOR_PID` (`-1`).

`NetworkManager.is_spectator()` is the runtime check. `mode` is
`Mode.SPECTATOR`. `local_player_id` stays `-1`.

#### Spectator scene contract

The same `GameBoardBase` works as the spectator's scene root — the
multiplayer/spectator branch in `_ready` already handles the no-host
case by deferring to `_on_client_ready()`. What you change is the seat
container roles inside `BoardLayoutSlot`:

```
GameBoard (spectator scene)
├── GameSession ...
└── BoardLayoutSlot
    ├── LeftSeat   (SeatContainer, role=PLAYER_0)
    └── RightSeat  (SeatContainer, role=PLAYER_1)
```

PlayerBoard auto-bind (`auto_bind=true`) is required — it walks up to
the seat, resolves the explicit player_id, subscribes to the
broadcast-cached PlayerState in `session.client_players`, and refreshes
when the host's state arrives.

#### What works today

- Spectator joins before or after the game starts (state broadcasts on
  every state change include all connected peers).
- Both hands face-up, full visibility into modifiers, log, etc.
- Multiple spectators per host (each peer just gets a SPECTATOR_PID
  entry in `peer_player_map`).
- Action submissions from a spectator are rejected by the host's
  `_rpc_submit_action` handler (sender_pid != current_player_id).

#### What's not yet supported

- Rejoining mid-game with an authoritative state snapshot (resync
  works only for seated players today).
- A built-in "spectate this room" UI in the main menu — designer
  builds their own spectator entry point.
- Dynamic role re-assignment by the host (e.g., promote spectator to
  seated opponent if the original opponent disconnects).

#### Building a spectator scene — step by step

**1. Create the scene from the base template.**

   - In the FileSystem dock, right-click `scenes/board/GameBoardBase.tscn`
     → `Open in New Scene` (or open it and `Scene → Save As…`).
   - Save as `scenes/board/SpectatorBoard.tscn`. Leave the root node
     named `GameBoard` — the cross-scene multiplayer contract requires
     it.

**2. Reconfigure the two seat containers.**

   - Click `BoardLayoutSlot/OpponentSeat` in the scene tree.
     - Inspector → `Role`: change from `OPPONENT` to `PLAYER_0`.
     - Rename the node to `LeftSeat` (cosmetic; doesn't affect logic).
   - Click `BoardLayoutSlot/LocalSeat` in the scene tree.
     - Inspector → `Role`: change from `LOCAL` to `PLAYER_1`.
     - Rename to `RightSeat`.

**3. Drop modules into each seat.**

   Inside `LeftSeat` (now PLAYER_0), instance:

   - `scenes/board/PlayerBoard.tscn` — set `auto_bind = true` and
     `is_mirrored = false`.
   - `scenes/board/hud/RageDisplay.tscn` — leave `player_id`
     untouched; the seat resolves it.
   - Whatever else makes sense (`DeckCountLabel`, `ThreatDisplay`,
     etc.).

   Inside `RightSeat` (now PLAYER_1), instance the same modules. Set
   `is_mirrored = true` on its PlayerBoard if you want the opponent at
   the top of the screen.

**4. (Optional) Add a swap-sides button.**

   Add a `Button` somewhere in the scene with text "Swap Sides". In
   the scene's controller script, connect its `pressed` signal to:

   ```gdscript
   func _on_swap_pressed() -> void:
       $BoardLayoutSlot/LeftSeat.swap()
       $BoardLayoutSlot/RightSeat.swap()
   ```

   Each `swap()` call flips the seat's role (PLAYER_0 ↔ PLAYER_1) and
   emits `role_changed(new_player_id)`. All modules under that seat
   re-resolve and re-bind to the new player. No reload, no flicker —
   the next state broadcast hits the freshly bound modules.

**5. Wire a launcher.**

   In whichever menu/lobby will spawn spectators, set the scene mode
   and load the spectator board:

   ```gdscript
   func _on_spectate_button_pressed() -> void:
       var ip := "192.168.x.y"  # collected from the user
       var err := NetworkManager.join_as_spectator(ip)
       if err != OK:
           push_error("Spectate connect failed: %d" % err)
           return
       NetworkManager.change_scene("res://scenes/board/SpectatorBoard.tscn")
   ```

   For online relay, replace `join_as_spectator` with the relay
   equivalent once you wire one (today only LAN is in place — the
   relay path follows the same `_rpc_register_as_spectator` handshake
   and is a small extension to `network_manager.gd`).

**6. (Optional) Hide unused HUD pieces.**

   Spectators don't need:

   - The action panel / Play Battle / Play Strategy / etc. buttons —
     spectators can't act.
   - The chat input (unless you want spectator chat — separate
     feature).
   - Concede / rematch buttons (handled by the seated players).

   Either delete those nodes from the spectator scene or set
   `visible = false`.

**7. Verify.**

   - Run the scene with `NetworkManager.mode = Mode.SPECTATOR` set
     manually for an editor-only smoke test (no real connection — the
     scene boots, modules find no session state yet, labels show 0).
   - For a real test: launch one host, one client, one spectator.
     Expected: spectator sees both hands face-up, labels update on
     every state change, swap button flips sides, action submissions
     from the spectator are silently rejected.

#### Spectator scene template

A minimal `spectator_board.gd` that extends `GameBoardBase`:

```gdscript
extends "res://scenes/board/game_board_base.gd"

@onready var _btn_swap: Button = $SwapSidesButton
@onready var _left_seat: SeatContainer = $BoardLayoutSlot/LeftSeat
@onready var _right_seat: SeatContainer = $BoardLayoutSlot/RightSeat


func _on_client_ready() -> void:
    # Spectator-specific setup. Called by GameBoardBase._ready when the
    # peer is not the host. For seated clients this is also where you'd
    # add their UI; here it's the spectator's setup.
    _btn_swap.pressed.connect(_on_swap_pressed)


func _on_swap_pressed() -> void:
    _left_seat.swap()
    _right_seat.swap()
```

That's it — module auto-bind handles everything else. Phase signals,
log messages, end-game panel, etc. are all wired by the inherited
`GameBoardBase`.

### Ready-made HUD primitives

`scenes/board/hud/` ships drop-in HUD scenes that all follow the
auto-bind pattern. Drop one in, configure via the inspector, done.

| Scene | Inspector | Binds to |
| --- | --- | --- |
| `RageDisplay.tscn` | `player_id`, `format_string` | `PlayerState.rage_changed` |
| `ThreatDisplay.tscn` | `player_id`, `format_string` | `rage_changed` + modifier signals |
| `DeckCountLabel.tscn` | `player_id`, `format_string` | `PlayerState.deck_changed` |
| `DiscardCountLabel.tscn` | `player_id`, `format_string` | `PlayerState.discard_changed` |
| `TurnNumberLabel.tscn` | `format_string` | `TurnManager.turn_started` |
| `PhaseLabel.tscn` | `format_string` | `TurnManager.phase_started` |
| `TurnTrackerView.tscn` | — | turn + phase signals; both players |
| `LogPanel.tscn` | `max_lines` | `log_message` from TurnManager + EffectHandler |
| `EndGamePanel.tscn` | — | `TurnManager.game_ended`; emits `rematch_pressed` / `menu_pressed` |
| `BoardSfx.tscn` | `sound_for_local_player_id` | every action / effect / turn signal → SfxManager |
| `ActionPanel.tscn` | — | drop-in 6-action panel + Cancel/Confirm + prompt; auto-wires to SelectionModeController via GameBoardBase |
| `HandSortButton.tscn` | `player_id` (overridden by SeatContainer) | sort the seat's hand using GameSettings sort order on press |

These are small and intentionally minimal — they're starting points,
not the final visual. To customize, copy the .gd, change the visuals,
keep the `_ready()` auto-bind block.

### HUD components — building your own

For most player-bound HUD labels, **extend `BoundLabel`** instead of
rolling your own auto-bind code. BoundLabel handles all the
session/seat resolution, signal subscription, host-vs-client timing,
seat-role-swap rebinding, and teardown. Subclass overrides one method:

```gdscript
extends BoundLabel

@export var format_string: String = "Rage: %d"

func _refresh(_session: GameSession, player: PlayerState) -> void:
    text = format_string % player.rage
```

That's a complete `RageDisplay` — about 5 lines.

For displays that need session-level data beyond a single PlayerState
(modifier sums, current_phase, etc.), the same `_refresh` callback
also receives the GameSession:

```gdscript
extends BoundLabel

@export var format_string: String = "Threat: %d"

func _refresh(session: GameSession, player: PlayerState) -> void:
    var base_threat: int = player.current_monster.get("threat", 0) if not player.current_monster.is_empty() else 0
    var threat: int = base_threat + player.rage * 5000
    if session.is_running() and session.effect_handler:
        threat += session.effect_handler.get_threat_level_modifier(player.player_id)
    text = format_string % threat
```

Inspector exposes a `Bindings` group with:
- `session_path: NodePath` — optional explicit session reference (else
  tree-walk via `BoardModule`)
- `player_id: int` — overridden by ancestor `SeatContainer` when
  present

For session-level state that isn't tied to a specific player (turn
number, phase banner, current-player indicator), extend
**`SessionBoundLabel`** instead. Same lookup + timing affordances,
no `player_id` / seat resolution, and the subclass wires whichever
session signals it cares about in `_bind(session)`:

```gdscript
extends SessionBoundLabel

@export var format_string: String = "Turn: %d"

func _bind(session: GameSession) -> void:
    session.turn_manager.turn_started.connect(_on_turn_started)
    _refresh()

func _on_turn_started(_pid: int) -> void: _refresh()

func _refresh() -> void:
    if _session and _session.game_state:
        text = format_string % _session.game_state.turn_number
```

For HUD components that aren't labels (custom widgets, animated
elements, multi-line UIs):

```gdscript
extends Label  # or whatever control type

@export var player_id: int = 0

func _ready() -> void:
    var session := BoardModule.find_session(self)
    if session == null:
        return
    # Wait for the host session to start, then bind. If the session is
    # already running by the time we add to tree, bind immediately.
    if session.is_running():
        _bind(session)
    else:
        # GameBoardBase doesn't currently emit a "session_started" signal;
        # for now, defer one frame and re-check.
        await get_tree().process_frame
        if session.is_running():
            _bind(session)

func _bind(session: GameSession) -> void:
    var player := session.get_player(player_id)
    if player == null:
        return
    player.rage_changed.connect(_on_rage_changed)
    _refresh(player)

func _on_rage_changed(_new_rage: int) -> void:
    var session := BoardModule.find_session(self)
    _refresh(session.get_player(player_id))

func _refresh(player: PlayerState) -> void:
    text = "Rage: %d" % player.rage
```

Drop into your scene tree, set `player_id` in the inspector, done.

### Action panel contract

Any node can be an action panel as long as it satisfies this contract:

**Signal:**
- `action_pressed(action: CardEnums.ActionType)` — emitted when the
  player presses an action button.

**Methods:**
- `set_action_buttons_visible(visible: bool)` — show / hide the action
  rows (used during effect prompts that take over the action area).
- `set_button_state(action: CardEnums.ActionType, enabled: bool, visible: bool)` —
  enable/disable individual buttons during selection mode.

The selection-mode flow on the host scene listens to `action_pressed`,
runs the rules check, and dispatches via `session.submit_action(...)`.

(There's no shared base class yet — the contract lives in this doc and
in code comments. A `SelectionModeController` may be extracted in a
future phase once two action-panel variants exist.)

## Adding a new prompt type

If you need an entirely new effect prompt (e.g. "select a multi-zone
range"), it requires changes across multiple layers:

1. **EffectHandler** (`scripts/game/effects/effect_handler.gd`):
   - Add a `signal X_requested(player_id, ...)` request signal.
   - Add a `func resolve_X(...)` method.
2. **MultiplayerSync** (`scripts/session/multiplayer_sync.gd`):
   - Add an `_rpc_X_requested(...)` forwarder pair.
   - Add an `_rpc_X_resolved(...)` forwarder pair.
3. **EffectUIRouter** (`scripts/session/effect_ui_router.gd`):
   - Add `"X"` to `_OVERLAY_KEYS`.
   - Add `_on_X_requested(...)` dispatcher (with the bot/remote/local
     filtering pattern).
   - Add `show_X(...)` entry-point that calls the registered handler.
   - Add `resolve_X(...)` callback that handles host-vs-client RPC routing.
   - Connect `effect_handler.X_requested` to `_on_X_requested` in `bind()`.
4. **Overlay** (your new scene):
   - Follow the auto-registration pattern from one of the existing
     overlays (`@export var prompt_key`, register in `_ready()`).
5. **Bot** (`scripts/bot/bot_player.gd`):
   - If the bot will encounter this prompt, add a handler.

Most of the work is mechanical. A scaffolding script could automate
steps 1–3; not built yet.

## Designer workflow

### Starting from GameBoardBase (recommended)

1. Open `scenes/board/GameBoardBase.tscn` in the editor.
2. **Save As** to your new scene path (e.g.
   `scenes/board/MobileGameBoard.tscn`). The root node is already named
   `GameBoard` — leave it alone.
3. Replace the script reference at the root with your own controller
   script (or extend `game_board_base.gd`).
4. Add your visual layout under `BoardLayoutSlot`.
5. Override the `_on_phase_started`, `_on_turn_started`,
   `_on_log_message`, `_on_game_ended`, `_on_awaiting_action`, etc.
   hooks in your script to update visuals.
6. F6 to play your scene. With `NetworkManager.mode = SOLO_BOT` set
   beforehand, you'll get a bot opponent and can play a real game.

### Replacing an overlay variant

1. Create a new overlay scene that fulfills the same prompt contract.
2. Set its `prompt_key` to the key it overrides (e.g. `"deck_search"`).
3. Drop it into your scene tree (alongside or replacing the default).
4. Either remove the default `DefaultOverlayPack` instance, OR set the
   default's `auto_register = false` so your custom one wins
   deterministically.

### Multiplayer matchmaking across variants

Two players can be on different GameBoard scenes (e.g. mobile + desktop)
and play multiplayer:

- Both peers' scenes must have root named `GameBoard`.
- Both must include `GameSession/MultiplayerSync` and
  `GameSession/EffectUIRouter` at those exact NodePaths.
- The peer running on mobile loads `MobileGameBoard.tscn`, the peer on
  desktop loads `DesktopGameBoard.tscn`. The `MultiplayerSync` NodePath
  is identical on both: `/root/GameBoard/GameSession/MultiplayerSync`.
  RPCs route correctly.
- `NetworkManager.change_scene()` is called per peer with their preferred
  scene file (this routing logic lives in `scripts/network/network_manager.gd`).

## Troubleshooting

**"GameSession parent is named 'X' — must be named 'GameBoard'"**
> The root of your scene isn't named `GameBoard`. Open the .tscn in the
> editor, click the root node, rename it. Or save-as from
> `GameBoardBase.tscn`.

**"BoardModule.find_router returned null"**
> Either the contract is broken (no `GameBoard/GameSession/EffectUIRouter`
> subtree), OR your module is being added before the GameSession's
> `_ready()` runs. The Godot order is children-first, so make sure your
> module is a descendant of the root, not a sibling.

**Auto-registered handler isn't firing**
> Check that:
> - The overlay is a descendant of the GameBoard root in the scene tree.
> - `auto_register = true` on the overlay (default).
> - No other handler registered for the same key after this one
>   (last-write-wins).
> - The router was bound: `effect_ui_router.bind(session, sync, pid)` in
>   the host scene's _ready().

**Multiplayer RPC not received on remote peer**
> Both peers must have the same NodePath for `MultiplayerSync`. Verify:
> - Both scenes have root named exactly `GameBoard`.
> - Both have `GameSession/MultiplayerSync` at that exact path (no rename,
>   no extra Control wrapper).
> - The `MultiplayerSync` script is `scripts/session/multiplayer_sync.gd`.

## Files referenced in this doc

- `scripts/session/board_module.gd` — tree-walk helpers
- `scripts/session/game_session.gd` — runtime owner
- `scripts/session/multiplayer_sync.gd` — RPC transport
- `scripts/session/effect_ui_router.gd` — effect prompt dispatcher
- `scenes/board/GameBoardBase.tscn` — pre-wired starting point
- `scenes/board/overlays/DefaultOverlayPack.tscn` — bundle of 7 standard overlays
- `scenes/board/overlays/*.gd` — individual overlay implementations (reference for `prompt_key` + `_on_router_show` pattern)
- `scenes/board/NewGameBoard.tscn` / `new_game_board.gd` — the smoke-test stub, an example of a minimal scene that uses the contract
- `scenes/board/GameBoard.tscn` / `game_board.gd` — the existing full-featured scene, an example of a scene that explicitly registers handlers (overrides the auto-registration default)
