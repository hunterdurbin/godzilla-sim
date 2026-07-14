# scenes/ — the presentation layer

Everything visual lives here. This layer depends on `scripts/` (engine,
session, services) — never the reverse. Domain dirs mirror the logic layer's
vocabulary.

## Convention: scene ↔ script mirror

A scene `FooBar.tscn` and its script `foo_bar.gd` live **in the same
directory with the same name** (PascalCase scene, snake_case script). Shared
scripts used by several scenes (e.g. `overlays/card_grid_viewer.gd`) are the
exception, not the rule.

## Domain map

| Dir | Contents | README |
|---|---|---|
| `board/` | The in-game board: GameBoard + PlayerBoard, `hud/`, `overlays/`, `modules/` | [board/README.md](board/README.md) |
| `cards/` | `Card.tscn` (`set_card_data_dict(dict)`) + `CardManager.tscn` (selection mode, drag source) | — |
| `deck/` | `Deck.tscn` deck widget | — |
| `slots/` | `Slot.tscn` (zone_number / slot_type / player_id) + drag-drop handler | — |
| `menus/` | App screens: **LoadingScreen (main scene)** → MainMenu, Options, Extras | [menus/README.md](menus/README.md) |
| `lobby/` | Multiplayer entry: LanLobby, OnlinePlay, OnlineLobby, PublicLobby | [lobby/README.md](lobby/README.md) |
| `deck_builder/` | DeckBuilder, DeckSelect + list/row/folder/bot-pool widgets | [deck_builder/README.md](deck_builder/README.md) |
| `replay/` | ReplayViewer | — |
| `server/` | ServerMain.tscn (dedicated server entry; logic in `scripts/server/`) | — |

Navigation between screens goes through `NetworkManager.change_scene(path)` —
paths are string literals, so **moving/renaming a scene requires a repo-wide
grep** (they fail only at runtime).

## Presentation gotchas (hard-won)

- Full-rect overlays need anchors baked in the .tscn (`anchors_preset=15` +
  grow flags) — setting them in `_ready` can leave the node 0×0.
- High `z_index` ≠ input priority: GUI picking is tree order; early-tree
  overlays need `_input` + `make_input_local` hit tests.
- Reparenting a card with a hover tween: kill the tween + reset scale first,
  zero anchors, use `global_position` after.
- Card badges must `hide()`, not `queue_free()` — deferred free races with
  node reuse.
- `Card.tscn` reverts to its default 150×210 outside a Container — wrap mini
  previews in an HBox (identify wrappers by meta, not name).
- AcceptDialog auto-sizes huge with autowrap/fit_content children —
  `popup_centered(size)` is a minimum, not a maximum.
