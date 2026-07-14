# scenes/board/ — the in-game board

Deeper architecture doc: [docs/game-board-architecture.md](../../docs/game-board-architecture.md).

## Anatomy

| Piece | Role |
|---|---|
| `GameBoard.tscn` / `game_board.gd` | Root scene for a match. Hosts a `GameSession` child (with `MultiplayerSync` + `EffectUIRouter` — contract validated by `scripts/tools/check_designer_contract.gd`), both PlayerBoards, action buttons, log/chat. Implements the `_board` duck-typed contract the session layer calls (see `scripts/session/README.md`) |
| `PlayerBoard.tscn` / `player_board.gd` | One player's playmat. Flat `LayoutContainer` whose children (Strategy1–3, RageBg/RageDisplay, CPDisplay, Zone1–8, Deck/Monster/DiscardInfo) are placed by fractional anchors matching the zones.svg layout; `zone_slots` 0-indexed via name lookup. `_update_layout()` sizes LayoutContainer at runtime (aspect-fit 1728:1008 + vertical crop of the SVG's empty band). P2 mirrors via `_apply_mirror()` flipping per-node anchors on both axes |
| `hud/` | Small bound widgets: phase/turn labels, rage/threat displays, deck/discard counters, hand sort |
| `overlays/` | Modal card UIs: zoom, select, deck search/arrange, discard/monster-deck/zone-stack viewers (three viewers share `card_grid_viewer.gd`), minimize chip, banners/toasts |
| `modules/` | Board submodules (BoardModule pattern) — see [modules/README.md](modules/README.md) |

## Extraction idiom (how game_board.gd sheds weight)

State forwards into GameSession via forwarding properties; modules find the
board through the named "GameBoard" subtree and read `_board._x` fields
(fields need `@warning_ignore("unused_private_class_variable")` on the
polymorphic implementations). **Methods the session layer calls stay on
game_board.gd as thin delegates** — the same surface must exist on
`tests/harness/stub_client_board.gd` and `scripts/server/headless_board.gd`.

## Editor WYSIWYG (@tool preview)

`player_board.gd` and `scenes/slots/slot.gd` are `@tool`: in the editor,
PlayerBoard runs only `_update_layout()` (so the anchored zones resolve to
real rects) and each Slot draws a labeled outline of its content rect;
toggle the whole preview via the `editor_preview` checkbox on the PlayerBoard
root (off collapses LayoutContainer back to the dormant .tscn state, which
also hides every outline — the flag is ignored at runtime);
`editor_zone_outline.gd` does the same for the plain-Control info areas
(DeckInfo/MonsterInfo/DiscardInfo). Rules for touching this code:

- Editor preview is **draw-only** (`_draw()` + `queue_redraw()`), never a
  mutation of child-node properties — the editor would save those as instance
  overrides in the scene.
- `_apply_mirror()` must never run in the editor: saved flipped anchors would
  be flipped again at runtime. The preview always shows P1 orientation (the
  P2 instance in GameBoard.tscn previews un-mirrored).
- All autoload access (`GameSettings`, `NetworkManager`, …) must sit behind
  `Engine.is_editor_hint()` guards — autoloads don't exist in the editor.
- Saving PlayerBoard.tscn / GameBoard.tscn may bake the offsets
  `_update_layout()` computed for LayoutContainer/BoardBg/GradientOverlay.
  Harmless (runtime recomputes them in `_ready()`), just diff noise.

## Validation notes

- `Slot.is_highlighted` is unreliable for validation (hover mutates it) —
  store valid indices in a dedicated var.
- Zone card ids are per-copy instance ids — compare with
  `CardUtils.base_id(card)`.
