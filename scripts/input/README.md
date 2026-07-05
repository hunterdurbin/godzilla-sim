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
| `glyph_db.gd` | `@tool` static lookup: physical action → glyph texture per controller type, joy-name → type detection, default logical→physical map. @tool-safe (no autoloads) so the editor can preview real glyphs. |
| `controller_glyph.gd` | `class_name ControllerGlyph` — the WYSIWYG scene-embedded glyph (`TextureRect`). In the editor it previews the actual Kenney texture for its exported `action` (`preview_type` flips art sets). At runtime it is visible only in gamepad mode, hides while its parent button is disabled, and refreshes on device switch / type change / rebind. Runtime-built UI constructs it with `ControllerGlyph.new()`. |

Related pieces elsewhere:

- `scripts/services/gamepad_helper.gd` — autoload **GamepadHelper**: last-used-
  device detection (gamepad vs mouse/touch; desktop-only mouse warp + cursor
  hide), the LIFO **focus-context stack** (screens/modals push a provider
  Callable; `refocus()` grabs focus only in gamepad mode so pointer users
  never see rings), and `make_pad_focusable(control)` for controls that must
  stay `FOCUS_NONE` under the mouse.
- `scenes/board/modules/gamepad_board_nav.gd` — board cursor over virtual
  regions (hand/zones/strategy); consumes `pad_nav_*`/`pad_confirm` and
  synthesizes the pointer path's signals (`CardManager.select_card_at`,
  `Slot.simulate_click`). Jailed to prompts via
  `SelectionController.selection_context_changed`.
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
