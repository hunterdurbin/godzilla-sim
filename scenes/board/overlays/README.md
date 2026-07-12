# scenes/board/overlays/ — modal card UIs

Overlays pop over the board for card-level interactions. Shared plumbing:
`overlay_grid_util.gd` (grid sizing + the controller focus meshes),
`overlay_hint_row.gd` (glyph+label pad-hint cluster, gamepad-mode-only —
also embedded in the board's choice and pending-effects panels as the
Select-toggle hint) and
`minimize_chip.gd` (collapse an overlay to a chip so the player can inspect
the board underneath; shows a B glyph in gamepad mode — B restores).

| Overlay | Purpose |
|---|---|
| `CardZoomOverlay` | Full-size card inspection (hover/long-press zoom) |
| `CardSelectOverlay` | Pick N cards (discard costs, effect targets) |
| `DeckSearchOverlay` | Search-your-deck effects |
| `DeckArrangeOverlay` | Reorder-top-of-deck effects |
| `DiscardViewOverlay` / `MonsterDeckViewOverlay` / `ZoneStackViewOverlay` | Read-only pile viewers — all three attach the shared `card_grid_viewer.gd` |
| `active_ability_banner.gd` / `turn_toast.gd` | Transient banners |

Conventions:

- Overlays are full-rect: bake `anchors_preset=15` + grow flags into the
  .tscn (not `_ready`).
- Effect flows AWAIT overlay close — a visible enabled "Close" button blocks
  phase advance until pressed (relevant to headless drivers/tests).
- Mini card previews inside overlays must be Container-wrapped or Card.tscn
  snaps to 150×210; tag wrapper nodes with meta, not names.
- Multiplayer: client-side pick results arrive as JSON (int enums → floats)
  — re-map to canonical dicts by id before use.

Controller navigation (see `scripts/input/README.md` for the architecture):

- Every card-grid overlay calls `GamepadHelper.register_modal(self,
  _pad_focus_provider)` in `_ready` — showing it pushes a focus context
  (suspends the board cursor), hiding pops it (View Board minimize included).
  Providers are LAZY (first selectable live card, else
  `find_first_focusable`) — grid cards are rebuilt every refresh, never
  capture them.
- `OverlayGridUtil.wire_overlay_focus(grid, top_chrome, bottom_chrome)` /
  `wire_two_grid_focus(...)` mesh the grid AND the chrome rows into one
  focus_neighbor cycle (toggles above, Skip/Confirm/Close below; hidden
  chrome is filtered per refresh). Chrome buttons are
  `make_pad_focusable`'d so pointer users never see focus rings.
  Those helpers mesh each chrome list as a HORIZONTAL row — chrome stacked
  vertically (e.g. `card_grid_viewer.gd`'s View Board above Close) must use
  `wire_band_stack` with one row band per button, or dpad-down skips the
  lower button.
- Rebuilds preserve the pad cursor: capture
  `OverlayGridUtil.focused_index(grid)` BEFORE clearing, restore with
  `focus_index(grid, idx, fallback)` (deferred + revalidated) after.
- Deck arrange pad model: A moves the focused card to the other pile, LB/RB
  (`pad_focus_log`/`pad_focus_tracker` — free while the board cursor is
  suspended) reorder within Keep; pure pile math in the `pad_toggle`/
  `pad_shift` statics.
- Card zoom is NOT a registered modal: it manually routes pad actions in
  `handle_input` (dpad browses modifier rows, A retargets, Y toggles
  badges) and swallows the mirrored ui_* directions so the grid focus mesh
  behind it can't move; B falls through to the board's cancel ladder.
  While visible it also polls the raw stick actions in `_process` (left
  stick pans grab-style like touch drag, right stick zooms, R3 quarter-turns
  the view) — `visibility_changed` drives both
  the polling and `GamepadInput.set_stick_nav_suppressed`, so the left
  stick stops injecting `pad_nav_*` for the duration (dpad keeps browsing
  the rows) and the claim can't leak when the board hides the overlay by
  setting `visible` directly.
- Cards show the pad cursor via `focus_entered` (attention border + hover
  raise, gamepad mode only — `card.gd`); overlay ScrollContainers bake
  `follow_focus = true` in the .tscn.
- Regression tests: `tests/unit/gamepad/test_overlay_grid_focus.gd` (mesh
  edges), `tests/ui/GamepadOverlayNavTest.tscn` (full pad drive of viewer /
  deck search / zoom / card select / deck arrange).
