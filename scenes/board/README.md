# scenes/board/ — the in-game board

Deeper architecture doc: [docs/game-board-architecture.md](../../docs/game-board-architecture.md).

## Anatomy

| Piece | Role |
|---|---|
| `GameBoard.tscn` / `game_board.gd` | Root scene for a match. Hosts a `GameSession` child (with `MultiplayerSync` + `EffectUIRouter` — contract validated by `scripts/tools/check_designer_contract.gd`), both PlayerBoards, action buttons, log/chat. Implements the `_board` duck-typed contract the session layer calls (see `scripts/session/README.md`) |
| `PlayerBoard.tscn` / `player_board.gd` | One player's playmat. Two rows — FrontRow: StrategyArea, Rage, Z8, Z7, Z6, Deck; BackRow: Monster, Z1–Z5, Discard (paths `Rows/BackRow/Zone1` etc.; `zone_slots` 0-indexed). P2 mirrors by moving BackRow to child index 0 |
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

## Validation notes

- `Slot.is_highlighted` is unreliable for validation (hover mutates it) —
  store valid indices in a dedicated var.
- Zone card ids are per-copy instance ids — compare with
  `CardUtils.base_id(card)`.
