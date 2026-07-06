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
  rather than blocking. Menu/UI maps plug into the same class later.
- `scenes/board/modules/board_cursor_map.gd` — **the board map**: the
  hand-editable adjacency table for both playmats (`bot_*`/`top_*` visual
  ids + `hand`). To change where the cursor goes, edit this one table.
- `scenes/board/modules/gamepad_board_nav.gd` — board cursor driven by the
  map; consumes `pad_nav_*`/`pad_confirm` and synthesizes the pointer
  path's signals (`CardManager.select_card_at`, `Slot.simulate_click`).
  Prompts (`SelectionController.selection_context_changed`) jail the cursor
  to their valid elements — skip-through keeps movement spatial, and a
  sorted-cycle fallback on left/right guarantees sparse valid sets stay
  fully reachable. Free browse covers every mapped stop (zones, strategy,
  rage, decks, discards, both boards) with live top-card preview; the hand
  auto-expands (dpad-down from the action panel enters it) and the cursor
  follows its card ref across sorts (`cards_reordered` + CardManager's
  `selectable_indices` resync).
- `scripts/tools/glyph_audit.gd` — EditorScript (File > Run on an open
  scene): lists/audits every ControllerGlyph and batch-switches previews.
- Glyph art: `assets/ui/input_glyphs/<type>/<position>.png` (Kenney Input
  Prompts, CC0 — see ATTRIBUTION.md there). Files are named by PHYSICAL
  position (`face_south.png`); the Switch label swap is baked into the slice.

## Default mapping

A/south = confirm · B/east = cancel · Y/north = inspect/zoom · X/west =
primary phase button · bumpers = board region / overlay paging · triggers =
own/opponent discard viewers · start = system menu · select = chat ·
dpad + left stick = navigation (fixed). Everything except nav is rebindable
in Options → Controller.

## Testing

`tests/unit/gamepad/` (glyph files exist per type, detect_type table, rebind
swap-on-conflict + persistence); `tests/ui/GamepadBoardNavTest.tscn` boots a
solo board and drives the cursor with injected actions. Headful glyph
placement: the `verify` skill with a synthetic `InputEventJoypadButton` to
force gamepad mode (`GameSettings.use_mobile_layout = true` for mobile).
