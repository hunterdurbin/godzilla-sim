# scripts/input — Controller/Gamepad Input

Two-layer action design (ported from Slay the Spire 2's input architecture):
physical `controller_*` actions are the ONLY ones bound to joypad events in
`project.godot`; game code listens exclusively to logical `pad_*` actions,
which `GamepadInput` injects at runtime. Rebinding is therefore a dictionary
swap, and every glyph re-resolves through one `input_rebound` signal.

## Files

| File | Role |
|---|---|
| `gamepad_input.gd` | Autoload **GamepadInput**. Translates physical presses/releases into logical `InputEventAction`s (`Input.parse_input_event`), mirrors `pad_confirm`/`pad_cancel`/`pad_nav_*` onto `ui_accept`/`ui_cancel`/`ui_*` (those ui_ actions are keyboard-only in `[input]`, so the mirror is the only joypad path — no double-firing), injects left-stick nav, runs the hold-repeat timer (joypad events never echo), detects the controller type from the joy name, and owns rebinding (`rebind`, `begin_capture`, `reset_to_defaults`; persisted per controller type in GameSettings `[controller]`). |
| `glyph_db.gd` | `@tool` static lookup: physical action → glyph texture per controller type, joy-name → type detection, default logical→physical map. @tool-safe (no autoloads) so the editor can preview real glyphs. Steam Input aware: "Steam Virtual Gamepad" names resolve the real hardware via `Input.get_joy_info()` vendor ids (fallback xbox — Steam emulates XInput); "Steam Deck" maps to the `generic` set, which is Kenney's Steam Deck art. Options → Controller has a manual "Button Icons" override (`GameSettings.controller_glyph_style`) for masked devices. Full Steam Input API is a future stage: `docs/steam_input_api.md`. |
| `controller_glyph.gd` | `class_name ControllerGlyph` — the WYSIWYG scene-embedded glyph (`TextureRect`). In the editor it previews the actual Kenney texture for its exported `action` (`preview_type` flips art sets). At runtime it is visible only in gamepad mode, hides while its parent button is disabled, and refreshes on device switch / type change / rebind. Runtime-built UI constructs it with `ControllerGlyph.new()`. |

Related pieces elsewhere:

- `scripts/services/gamepad_helper.gd` — autoload **GamepadHelper**: last-used-
  device detection (gamepad vs mouse/touch; desktop-only mouse warp + cursor
  hide), the LIFO **focus-context stack** (screens/modals push a provider
  Callable; `refocus()` grabs focus only in gamepad mode so pointer users
  never see rings), `make_pad_focusable(control)` for controls that must
  stay `FOCUS_NONE` under the mouse, and **`register_modal(surface)`** — the
  one-liner every dialog/popup/prompt uses to take controller focus while
  visible (default providers: ConfirmationDialog → Cancel, AcceptDialog →
  OK, PopupMenu → self-navigating). `gui_focus_owner()` is the
  embedded-window-aware focus lookup (dialogs are their own viewports).
- `scripts/input/cursor_map.gd` — **CursorMap**: generic directional
  navigation graph (element id → up/right/down/left candidate lists).
  Multi-candidate directions tie-break by the **last-10-visited history**
  (the cursor returns where it came from), then list order; invalid/hidden
  elements are traversed *through* (same direction, bounded, cycle-guarded)
  rather than blocking. `set_map()` swaps edges without losing history.
  Menu/UI maps plug into the same class later.
- `scenes/board/modules/board_nav_graph.gd` — **BoardNavGraph**: builds the
  ONE graph covering everything the cursor can rest on — both playmats
  (`bot_*`/`top_*` visual ids), hand cards (`hand_<i>`), action-panel
  buttons + hand stacks (`ap_*`), the corner utility column (`sys_*`), the
  log/chat panel (`log_panel`), tracker labels (`trk_<i>`) and choice
  buttons (`choice_<i>`). To change where the cursor goes, edit its tables
  (`PLAYMAT`, `DESKTOP_UI`, `MOBILE_UI`); the `"hand"`/`"tracker"`
  sentinels expand at build time (nearest-card-by-X hand entry). @tool-safe
  and pure — unit tests and the editor overlay feed it fake rects.
- `scenes/board/modules/gamepad_board_nav.gd` — board cursor driven by the
  graph; consumes `pad_nav_*`/`pad_confirm` and synthesizes the pointer
  path's signals (`CardManager.select_card_at`, `Slot.simulate_click`,
  `Button.pressed`). **THE FOCUS INVARIANT**: while the board is the top
  focus context, no control holds real focus (its provider answers null) —
  mirrored `ui_*` events therefore can't double-drive anything; real focus
  exists only inside registered modals and the chat LineEdit while typing.
  Prompts (`SelectionController.selection_context_changed`) jail the cursor
  to their valid elements — skip-through keeps movement spatial, and a
  sorted-cycle fallback on left/right guarantees sparse valid sets stay
  fully reachable; choice/confirm prompts jail onto the `choice_<i>` /
  Confirm button nodes. Free browse covers every stop with live top-card
  preview; hovering a hand card raises it via the card's own mouse-hover
  handlers, and the cursor follows its card ref across sorts. When the
  hovered card is played, the cursor moves to the card on its left, else
  its right, else the Sort button; when the button under the cursor
  disables (`action_buttons_changed`), it relocates deterministically
  (history → spatial neighbor → End Main → Z2).
- `scenes/board/modules/hand_hint_bar.gd` — **HandHintBar**: bottom-left
  glyph+label cluster (A Play / LT Rage / RT Invade) while the cursor
  free-browses a hand card on the local player's action; rows filtered per
  card through `SelectionController.hand_card_hint_actions()` (button-enabled
  state doubles as the "awaiting main-phase action" gate, so pending
  effects/prompts and the opponent's turn blank it). Hidden on mobile and in
  pointer mode.
- `scenes/board/modules/nav_debug_overlay.gd` — **NavDebugOverlay**: F3 in
  a debug build paints the live graph over the board (green = cursor,
  blue = valid, red = prompt-jailed, gray = hidden; edge arrows + state
  HUD). In the editor, check `editor_preview` on the GameBoard.tscn node to
  render the static tables. `scripts/tools/nav_graph_audit.gd` (File > Run)
  lints the tables for dangling/one-way/unreachable edges.
- `scenes/board/overlays/` — every in-game modal overlay is pad-navigable:
  card grids + their chrome (toggles / Skip / Confirm / Close) mesh into one
  focus_neighbor cycle via `OverlayGridUtil.wire_overlay_focus`, each
  overlay is a registered modal (focus context suspends the board cursor,
  View Board minimize pops it, B restores via the chip), deck arrange has an
  A-toggle + LB/RB-reorder model, and the card zoom routes dpad/A/Y
  manually. Details: `scenes/board/overlays/README.md`.
- `scripts/tools/glyph_audit.gd` — EditorScript (File > Run on an open
  scene): lists/audits every ControllerGlyph and batch-switches previews.
- Glyph art: `assets/ui/input_glyphs/<type>/<position>.png` (Kenney Input
  Prompts, CC0 — see ATTRIBUTION.md there). Files are named by PHYSICAL
  position (`face_south.png`); the Switch label swap is baked into the slice.

## Default mapping

A/south = confirm (and, on a hovered hand card, PLAYS it by its type —
monster/battle/strategy) · B/east = cancel · Y/north = inspect/zoom ·
X/west = primary phase button · **LB = focus game log/chat** (dpad scrolls,
A enters the chat field, LB/B returns the cursor where it was) · **RB =
focus turn tracker** (dpad walks the labels, A toggles that auto setting,
RB/B returns) — both bumpers work DURING prompts (the jail is suspended
inside the module and restored on return) and slide the matching tray open
on mobile · LT = pad_play_card_rage (discard hovered monster for rage) ·
RT = pad_play_card_invasion (discard hovered card to invade) · start =
system menu · select = chat · dpad + left stick = navigation (fixed).
There is NO region/group cycling — the screen layout IS the navigation:
walking off any edge crosses into the neighboring area (board rows ↕ hand ↔
hand buttons ↔ action panel; log panel left, tracker/system column right).
Everything except nav is rebindable in Options → Controller. Discard piles
are cursor stops on the board map — confirm on one opens its viewer.

## Testing

`tests/unit/gamepad/` (glyph files exist per type, detect_type table, rebind
swap-on-conflict + persistence); `tests/ui/GamepadBoardNavTest.tscn` boots a
solo board and drives the cursor with injected actions. Headful glyph
placement: the `verify` skill with a synthetic `InputEventJoypadButton` to
force gamepad mode (`GameSettings.use_mobile_layout = true` for mobile).
