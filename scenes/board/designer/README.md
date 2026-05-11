# Designer Workflow

This folder is your scratch space for building a custom GameBoard. The
three starter scenes here all inherit from production templates, so
you get a working board out of the box and customize from there
without touching shared code.

## TL;DR — 60-second start

1. Open `scenes/ui/MainMenu.tscn` in the editor and **F5** to run.
2. Pick decks, click the 🧪 button next to **Solo v Bot**.
3. `DesignerGameBoard` loads. Play through. Now go customize.

If multiple `*GameBoard.tscn` variants exist under `scenes/board/`,
the menu shows a picker dropdown — your changes aren't fighting with
the production scene.

## What's here

| File | Inherits | Purpose |
| --- | --- | --- |
| `DesignerGameBoard.tscn` | `GameBoardTemplate.tscn` | Top-level scene — root layout, HUD, overlays, action panel, etc. |
| `DesignerPlayerBoard.tscn` | `PlayerBoardTemplate.tscn` | One player's side of the board — zones, rage display, CP labels, deck/discard/monster info. |
| `DesignerOverlayPack.tscn` | `DefaultOverlayPack.tscn` | Bundle of modal scenes (deck search, card select, deck arrange, choice prompt, monster rank-up, card zoom, etc.). |

## The big idea

Three layers of customization, in order of how often you'll touch them:

1. **Inspector tweaks** — colors, fonts, sizes, anchor positions. No
   code, no scene structure changes. You'll do this 80% of the time.
2. **Scene-tree edits** — add/remove children, swap component
   variants, reposition nodes, change parents. You'll do this 15%.
3. **Script overrides** — extend a controller and override one of
   the protected `_on_X` hooks (`_on_phase_started`, `_on_turn_started`,
   `_on_log_message`, `_on_game_ended`, etc.). You'll do this 5% — only
   when you want gameplay-specific visual reactions.

## 1. Inspector tweaks (most common path)

The templates expose **everything that used to be hardcoded** as
`@export` fields. Click any node, look at the Inspector, find the
relevant group:

### PlayerBoard inspector groups

Open `DesignerPlayerBoard.tscn` and click the root `PlayerBoard`:

- **Layout fitting**: `maintain_aspect` (default `false`),
  `aspect_ratio`, `content_rect_normal/mirrored`. With
  `maintain_aspect = false` (default for designer scenes), the
  LayoutContainer fills its parent via editor anchors — what you see
  in the editor preview is what runs. With `maintain_aspect = true`
  (production default), the runtime auto-fits to a 1728×1008 playmat
  aspect.
- **Battle zones / Strategy slots**: every `ZoneN` and `StrategyN`
  Slot is editor-placeable as an inherited child. Drag them, change
  their `accept_cards`, etc.
- **Rage block / Threat block / CP block**: VBox/HBox containers with
  Labels. Edit positions, fonts, colors directly.
- **Info zones**: `deck_display`, `discard_display`,
  `monster_info_display` Controls. Plus `deck_count_badge`,
  `discard_count_badge`, `monster_deck_count_badge` — editor-placed
  Labels you can fully restyle. Hidden by default; show on hover.
- **Count badges** (fallback styling): used only if the editor-placed
  badges above are unset.
- **Info zone borders**: `enable_info_borders` toggle + color +
  width. Disable if you want to use a Panel + StyleBoxFlat instead.
- **Deck stack**: `enable_deck_stack` toggle + `max_layers` +
  `layer_shift`. Disable to use a custom counter / texture.

### HUD primitives

Each HUD scene under `scenes/board/hud/` has its own knobs:

- **`HandSlot.tscn`**: `auto_position` (default `false`), `anchor_edge`,
  `width_pct`. With `auto_position = false`, the editor-placed
  Node2D coordinates are preserved.
- **`CardManager` (HandSlot extends this)** — the layout knobs:
  - **Hand bounds → `left_anchor` / `right_anchor`**: two ways to
    set them:
    1. Drag two `Marker2D` (or any `Node2D`) into these inspector
       slots, OR
    2. Add two `Marker2D` children named exactly `LeftAnchor` and
	   `RightAnchor` — they're auto-detected, no inspector wiring
	   needed.
	The hand fills the span between their global X positions. Editor
	draws a cyan rectangle showing the bounds live. **Anchors win
	over `max_width`** when both are present.
  - **`hand_alignment`** (LEFT / CENTER / END): when cards fit
	comfortably, this controls where the cluster sits within the
	bounds. Orange dot in the editor marks the reference edge.
  - **`card_spacing`**: pixel gap between adjacent card centers when
	they fit comfortably.
  - **`min_card_gap`**: floor for the gap when cards must overlap
	(defaults negative so cards visibly stack).
  - **`card_scale`**: uniform scale applied to incoming cards. Use
	e.g. `Vector2(0.7, 0.7)` for an opponent-style smaller hand.
  - **`default_face_down`**: mark every added card face-down. For
	opponent hand displays.
  - **`draw_bounds_in_editor`**: toggle the debug rect visualization.
- **`HoverPreview.tscn`**: `auto_layout`, `card_aspect_ratio`,
  `padding`, `rotate_strategy`. Disable `auto_layout` for fully
  scene-driven card preview placement.
- **`ChoicePromptOverlay.tscn`**: `button_min_size`,
  `button_separation`. Affects the dynamic option buttons.
- **`SettingsTray.tscn`**: per-row visibility toggles
  (`show_auto_draw`, `show_auto_phase_advance`, etc.).
- **`SaveButton.tscn`** / **`HandSortButton.tscn`** / etc.: minimal
  config; restyle via inspector overrides on the inherited Button.

Full list with descriptions: [`docs/new_game_board.md`](../../../docs/new_game_board.md)
§ "Ready-made HUD primitives".

## 2. Scene-tree edits

### Move things around

Open `DesignerGameBoard.tscn`. The whole inherited tree is visible.
Click any node → drag, anchor, restyle. Examples:

- **Move the LogPanel** from bottom-right to top-left: change
  `anchors_preset` on `LogPanel`.
- **Hide the SettingsTray**: select it, uncheck `Visible`.
- **Replace the ActionPanel with your own variant**: delete the
  inherited `ActionPanel`, drop your `MyActionPanel.tscn` in its
  place. (As long as your scene emits `action_pressed`,
  `cancel_pressed`, `confirm_pressed` signals, the
  SelectionModeController auto-detects it.)

### Different layouts per seat

The `LocalSeat` (bottom) and `OpponentSeat` (top) each contain a
`PlayerBoard` instance. To use **different visuals per side**:

1. **Editor-driven path** — open `DesignerGameBoard.tscn`, click the
   inherited `OpponentSeat/.../PlayerBoard` instance, in the
   inspector click the scene-folder icon and swap to e.g.
   `MyOpponentPlayerBoard.tscn` (which you've created via
   `File → New Inherited Scene → DesignerPlayerBoard.tscn`).
2. **Inspector-driven path** — delete the inherited `PlayerBoard`
   children. On each `SeatContainer`, set `player_board_scene` in the
   inspector. Runtime auto-instantiates per-seat.

### Custom overlay variants

To restyle a specific overlay (e.g., your own deck search UI):

1. `File → New Inherited Scene → scenes/board/overlays/DeckSearchOverlay.tscn`
2. Save as `MyDeckSearchOverlay.tscn`.
3. Restyle the inherited tree.
4. Open `DesignerOverlayPack.tscn`. Right-click the inherited
   `DeckSearchOverlay` child → "Change Scene File…" → pick your
   `MyDeckSearchOverlay.tscn`. Keep the **node name** the same; it's
   how the EffectUIRouter routes to it.

Or skip the pack entirely: drop your custom overlay anywhere under
`DesignerGameBoard.tscn`. As long as `auto_register = true` and
`prompt_key` matches the engine's signal name (`deck_search`,
`card_select`, `choice`, etc.), it self-registers with the router.

## 3. Script overrides

Need gameplay-driven visual reactions (a banner when a phase changes,
camera shake on counter-success, etc.)?

1. Create `scenes/board/designer/designer_game_board.gd` extending
   `game_board_template.gd`:

   ```gdscript
   extends "res://scenes/board/game_board_template.gd"

   func _on_turn_started(player_id: int) -> void:
	   super(player_id)
	   # your custom turn-start animation / SFX trigger
   ```

2. Open `DesignerGameBoard.tscn` root → inspector → set the script
   to your new `designer_game_board.gd`.

The protected hooks available in `game_board_base.gd`:

- `_on_phase_started(phase: CardEnums.GamePhase)`
- `_on_phase_ended(phase: CardEnums.GamePhase)`
- `_on_turn_started(player_id: int)`
- `_on_awaiting_action(valid_actions: Array)`
- `_on_game_ended(winner_id: int, reason_key: String)`
- `_on_log_message(token)`
- `_on_confirmation_requested(prompt: String, setting: String)`
- `_on_view_board_request(overlay: Control)`

Each is empty in the base; override only what you care about. Always
call `super(...)` if you want the base's default behavior preserved.

## Adding a brand-new GameBoard variant

`File → New Inherited Scene → DesignerGameBoard.tscn`. Save as
`scenes/board/designer/MyMobileGameBoard.tscn` (or any subfolder of
`scenes/board/`). The 🧪 picker scans recursively — it'll appear in
MainMenu without code changes.

## What lives in code vs scene

| In the scene tree (you edit) | In code (don't worry about it) |
| --- | --- |
| Zone positions, anchors, rotations | Card draw / discard logic |
| Label fonts, colors, outlines | Turn / phase progression |
| Sub-component visibility | Drag-to-zone resolution |
| Custom variants of any HUD scene | Bot decisions |
| Overlay registration via `prompt_key` | RPC routing for multiplayer |
| Whether to auto-fit aspect / draw borders / spawn deck stack | Effect resolution |

## Common tasks cheat sheet

| Task | Where |
| --- | --- |
| Move a battle zone | `DesignerPlayerBoard.tscn → LayoutContainer/ZoneN`, drag in editor |
| Change rage label color | `DesignerPlayerBoard.tscn → LayoutContainer/RageDisplay/RageRow/RageLabel`, theme override |
| Disable the deck stack visualization | `DesignerPlayerBoard.tscn → root → enable_deck_stack = false` |
| Replace the playmat texture | `DesignerPlayerBoard.tscn → BoardBg.texture` (and/or `LayoutContainer/Background.texture`) |
| Make opponent board look different | Create `MyOpponentPlayerBoard.tscn` inheriting from `PlayerBoardTemplate.tscn`; assign to OpponentSeat |
| Change choice button style | `DesignerOverlayPack.tscn → ChoicePromptOverlay → button_min_size / button_separation`, or restyle the panel |
| Add a custom prompt overlay | New scene with `auto_register = true`, matching `prompt_key`, drop into the tree anywhere |
| React to phase changes visually | Custom .gd extending `game_board_template.gd`, override `_on_phase_started` |

## The hard rule: cross-scene multiplayer

The **root node of every GameBoard scene must be named `GameBoard`**
(not the .tscn filename). The network layer routes RPCs through the
NodePath `GameBoard/GameSession/MultiplayerSync` — that name has to
match between the host and client peers' loaded scenes.

Inheritance from `GameBoardTemplate` automatically satisfies this.
Just don't rename the root node.

`docs/new_game_board.md` § "Cross-scene multiplayer contract" covers
this in depth.

## Reference docs

- [`docs/new_game_board.md`](../../../docs/new_game_board.md) — full
  technical reference: HUD primitives, BoundLabel base class,
  SeatContainer roles, EffectUIRouter handler keys, scene
  inheritance pitfalls.
- [`scripts/session/board_module.gd`](../../../scripts/session/board_module.gd) — tree-walk lookup
  helpers (`find_session`, `find_router`, `find_seat`,
  `get_card_scene`).
- [`scripts/session/seat_container.gd`](../../../scripts/session/seat_container.gd) — `Role` enum
  semantics (LOCAL / OPPONENT / PLAYER_0 / PLAYER_1).
