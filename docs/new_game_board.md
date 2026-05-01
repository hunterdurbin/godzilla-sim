# Building a new GameBoard scene

This is the canonical reference for designers / developers building a new
GameBoard scene (mobile, desktop, VR, themed variants, etc.). It covers the
cross-scene multiplayer contract, the module composition pattern, and how
to add new variants of overlays / HUD / action panels.

## TL;DR

1. Copy `scenes/board/GameBoardBase.tscn` (or extend it via scene
   inheritance) as your starting point.
2. Add visual layout into the `BoardLayoutSlot` Control.
3. Override the `_on_X` hooks in your scene's script to update visuals
   when game signals fire.
4. Drop overlay scenes / HUD components / action panels anywhere in the
   tree — they self-bind via tree-walk.
5. Save your scene with the root node named `GameBoard` (this is mandatory
   — see "Cross-scene multiplayer contract" below).

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

These are small and intentionally minimal — they're starting points,
not the final visual. To customize, copy the .gd, change the visuals,
keep the `_ready()` auto-bind block.

### HUD components — building your own

For HUD components beyond the primitives above (custom rage meter,
themed threat display, animated deck stack, etc.):

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
