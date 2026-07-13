# scripts/input — Controller/Gamepad Input

Two-layer action design (ported from Slay the Spire 2's input architecture):
physical `controller_*` actions are the ONLY ones bound to joypad events in
`project.godot`; game code listens exclusively to logical `pad_*` actions,
which `GamepadInput` injects at runtime. Rebinding is therefore a dictionary
swap, and every glyph re-resolves through one `input_rebound` signal.

## Files

| File | Role |
|---|---|
| `gamepad_input.gd` | Autoload **GamepadInput**. Translates physical presses/releases into logical `InputEventAction`s (`Input.parse_input_event`), mirrors `pad_confirm`/`pad_cancel`/`pad_nav_*` onto `ui_accept`/`ui_cancel`/`ui_*` (those ui_ actions are keyboard-only in `[input]`, so the mirror is the only joypad path — no double-firing), injects left-stick nav, runs the hold-repeat timer (joypad events never echo), detects the controller type from the joy name, and owns rebinding (`rebind`, `begin_capture`, `reset_to_defaults`; persisted per controller type in GameSettings `[controller]`). **`set_stick_nav_suppressed(bool)`** turns the left-stick→`pad_nav_*` injection off while a surface polls the raw axes itself (the card zoom overlay pans with it; dpad nav is unaffected) — flushing held directions with release twins so hold-repeat can't fire phantoms; `GLYPH_ONLY` maps the display-only `pad_stick_pan`/`pad_stick_zoom` pseudo-actions to the lstick/rstick glyphs for hint rows. Text fields: LineEdits fence pad actions only while `is_editing()` — a **meshed** field (focus_neighbor wired) can hold pad focus idle (GamepadHelper unedits it on arrival so passing through never pops a virtual keyboard), A starts editing (swallowed; this is where platform OSKs appear), and any dpad/B/select press while editing unedits in place, keeping the cursor on the field. Unmeshed fields (board chat, dialog inputs) keep focus-means-typing and the escape releases focus. Editable TextEdits always fence while focused. |
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
  For Window surfaces, `register_modal` also forwards `window_input` back
  through the device tracker and `GamepadInput.translate_event` — a focused
  embedded Window swallows input BEFORE the root viewport's
  `_input`/`_unhandled_input` stages, so without the forwarding the pad is
  dead inside every dialog — and hooks the window's own `gui_focus_changed`
  into the LineEdit unedit fence (an embedded Window is its own viewport,
  invisible to the root-viewport hook, so meshed fields inside dialogs
  would otherwise start editing when the dpad lands on them).
  **`wire_pad_close(popup, on_close)`** is the one-liner B-close: it acts on
  the LEADING cancel press (`is_cancel_press` — the raw physical button
  pad_cancel is bound to, the injected `pad_cancel`, or a keyboard-ESC
  `ui_cancel`) and calls `swallow_cancel_twins()` so the mirrored twins that
  follow die everywhere (`is_swallowed_cancel` checks in handlers plus a
  root `_input` eater) instead of leaking into the surface underneath. It
  refuses to close while a text field is editing — B escapes the field
  instead, and `GamepadInput._escape_text_field` stamps the same swallow so
  the escape press can't also close. Screen-level back handlers follow the
  same pattern in `_unhandled_input` (act on `pad_cancel`/`ui_cancel`,
  check `is_swallowed_cancel` first, stamp on action). A on the focused
  button remains a valid pad path out of any dialog (`close_on_escape`
  only reacts to real key events, not the mirrored `ui_cancel` action).
- `scenes/deck_builder/` — the deck builder meshes both card grids and all
  chrome with `OverlayGridUtil.wire_band_stack` (wrappers opt in via
  `GRID_CARD_META`), LB/RB cycle left panel / deck / pool,
  X (`pad_end_main`) is the contextual secondary (remove-all / To Main /
  To Monster / remove-from-pool), and `DeckBuilderPadHints` feeds the
  bottom hint row. Regression test:
  `tests/ui/DeckBuilderPadNavTest.tscn` (headless).
- `scenes/deck_builder/deck_list_view.gd` — the deck-picker expanded gallery
  (opened from the pickers on the main menu, lobbies, and deck builder)
  self-meshes on every rebuild (`_wire_pad_mesh`): the host `✕` band
  (injected via `extra_top_band`), the search/format/density row, then one
  band per folder header / deck row (rows carry their `⋯` button, exposed by
  `DeckRow.pad_focus_targets()`). The outer view's `_unhandled_input` closes
  the overlay on the LEADING `pad_cancel` (swallowing twins; text editing
  defers to the escape fence). `FolderPickerDialog` meshes its folder
  choices / new-folder edit / OK-Cancel and gets `wire_pad_close`
  (`queue_free` — the dialog is transient). Covered by the gallery tour in
  `tests/ui/DeckBuilderPadNavTest.tscn`.
- `scenes/menus/extras.gd` — the Extras screen and all of its runtime-built
  PopupPanel sub-views (replay/save/log lists, hosting lobby, confirm/label/
  player-choice dialogs) are pad-navigable: each popup passes a provider to
  `register_modal` (lists land on the first row's info button, confirms on
  Cancel), `_wire_list_pad` re-meshes the dynamic rows after every rebuild
  (with (row, col) pad-cursor restore and scroll follow-focus), and
  `GamepadHelper.wire_pad_close` gives every popup the leading-pad_cancel
  B-close — with real teardown where Cancel has one (hosting lobby
  disconnects, log list frees). Regression test:
  `tests/ui/ExtrasPadNavTest.tscn`.
- `scenes/replay/replay_viewer.gd` — screen focus context landing on
  Play/Pause; one `wire_band_stack` mesh over Exit / both hand rows /
  transport buttons / the two sliders (sliders sit in their OWN bands —
  they consume ←/→ for their value, so ↑/↓ is the only way on and off).
  Hand rows rebuild every snapshot: `_render_snapshot` re-meshes and
  restores the pad cursor by (grid, index). Bumpers step one snapshot
  (LB back / RB forward) and triggers jump a whole turn (LT / RT) from
  anywhere on the screen, gated on being the top context. Hand cards are
  `make_pad_focusable`d — focus mirrors hover (preview + scroll-into-view),
  Y zooms via the card's focused `pad_inspect` path. The zoom overlay is a
  null-provider modal whose `_input` branch swallows the pad twins (focus
  stays on the card behind the dim); the gallery mirrors
  `card_grid_viewer.gd` (`wire_overlay_focus`, stacked-toggle rebuild keeps
  the grid index, B restores the opener). `ReplayViewerPadHints` feeds a
  ctx-driven hint row floating above both overlays. Regression test:
  `tests/ui/ReplayViewerPadNavTest.tscn`.
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
  log/chat panel (`log_panel`), tracker labels (`trk_<i>`), choice
  buttons (`choice_<i>`) and pending-effect stack rows (`stack_<i>`, chained
  into `choice_0` while a choice is open). To change where the cursor goes,
  edit its tables (`PLAYMAT`, `DESKTOP_UI`, `MOBILE_UI`; `ZONE_JAIL_EDGES`
  is dormant — zone prompts free-roam now, see below); the
  `"hand"`/`"tracker"` sentinels expand at build time (nearest-card-by-X
  hand entry). @tool-safe and pure — unit tests and the editor overlay feed
  it fake rects.
- `scenes/board/modules/gamepad_board_nav.gd` — board cursor driven by the
  graph; consumes `pad_nav_*`/`pad_confirm` and synthesizes the pointer
  path's signals (`CardManager.select_card_at`, `Slot.simulate_click`,
  `Button.pressed`). **THE FOCUS INVARIANT**: while the board is the top
  focus context, no control holds real focus (its provider answers null) —
  mirrored `ui_*` events therefore can't double-drive anything; real focus
  exists only inside registered modals and the chat LineEdit while typing.
  Device takeover enforces it symmetrically (GamepadHelper): flipping to
  pointer releases focus, and flipping back to gamepad releases whatever a
  mouse click focused in between (the pointer-flip release runs BEFORE the
  click lands on its button) — otherwise the `ui_*` mirrors walk a second
  focus ring around the panel next to the cursor. Provider-backed contexts
  re-grab via the deferred `refocus()`.
  Prompts (`SelectionController.selection_context_changed`) pick where the
  cursor lands and which elements confirm acts on. Zone and strategy
  targeting (`card_to_zone`/`zone_target`/`zones_target`/`strategy_target`)
  leave the WHOLE board walkable — the player can inspect any state
  mid-decision; the prompt's element set only picks the landing element and
  gates confirm (A off the valid set is a no-op — slot clicks self-gate on
  selection mode, and `card_to_zone` additionally checks the cursor is on
  the target board so an opponent zone at the same index can't misplay).
  The old sealed-graph jail (`BoardNavGraph.ZONE_JAIL_EDGES` via the
  `zone_jail_side` ctx key) is dormant: the live board always passes `""`.
  The remaining prompts still jail movement — hand modes to the valid
  cards, choice/confirm onto the `choice_<i>` / Confirm button nodes (the
  choice jail also spans the `stack_<i>` rows).
  **Finalizing multi-selects**: X (`pad_end_main` →
  `SelectionController.press_primary_button()`) presses Confirm/Skip from
  anywhere (`zones_target`, hand multi-discard, skip-able prompts) — no
  need to walk to the button, though during free-roam prompts the cursor
  can also reach Confirm and press it with A. The Confirm button's
  ControllerGlyph is context-aware (`_emit_ctx` flips its `action`):
  it shows `pad_end_main` during those prompts and `pad_confirm` only in
  the pass-confirmation jail, where the cursor sits on the button itself.
  **Select toggle**: while the effects area is up (choice prompt, or
  pending-effect rows in free browse), Select cycles the cursor between it
  and the board, remembering both sides; during a mandatory choice the
  board side is a READ-ONLY roam (dpad + Y; A opens the pile/stack viewers
  like the mouse; X/LT/RT dead, B or Select
  returns) — `OverlayHintRow`s inside both panels show the Select glyph
  naming the destination. Free browse covers every stop with live top-card
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
RB/B returns) — both bumpers work DURING prompts (movement stays inside the
bumper region until return; any prompt jail is restored after) and slide the matching tray open
on mobile · LT = pad_play_card_rage (discard hovered monster for rage) ·
RT = pad_play_card_invasion (discard hovered card to invade) · start =
system menu · select = chat, or — while the effects area (choice prompt /
pending-effects panel) is up — cycles the cursor between it and the board
(chat stays reachable via LB → A) · dpad + left stick = navigation (fixed) ·
**sticks in the card zoom**: while the zoom overlay is open the left stick
pans the card (grab-style, dragging the card like touch; nav injection is
suppressed, dpad still browses the modifier rows), the right stick zooms
(up in / down out), and R3 (right-stick press) rotates the card 90° — all
fixed, not rebindable (R3 is deliberately absent from REBIND_CAPTURABLE).
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
