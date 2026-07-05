# Phase 4 — scenes/ re-slice

**Goal:** split the `scenes/ui/` grab-bag into screen-flow domains and fold
`scenes/managers/` into `scenes/cards/`. Presentation tree ends up sliced by
the same domain vocabulary as `scripts/`.

## Moves (git mv, with `.uid` twins; scenes move with their same-name scripts)

| Destination | From `scenes/ui/` (scene + script pairs) |
|---|---|
| `scenes/menus/` | LoadingScreen (MAIN SCENE), MainMenu, Options, Extras |
| `scenes/lobby/` | LanLobby, OnlineLobby, OnlinePlay, PublicLobby |
| `scenes/deck_builder/` | DeckBuilder, DeckSelect, deck_list_view.gd, deck_row.gd, folder_picker_dialog.gd, bot_pool_view.gd |
| `scenes/replay/` | ReplayViewer + replay_viewer.gd |
| `scenes/cards/` | everything in `scenes/managers/` (CardManager.tscn + card_manager.gd — LIVE, used by GameBoard/PlayerBoard/hand/deck) |

`ls scenes/ui/` first and map any file the table misses to the fitting domain
(record in STATE.md). Delete emptied `scenes/ui/` and `scenes/managers/`.

## project.godot

- [ ] `run/main_scene="res://scenes/menus/LoadingScreen.tscn"`

## Path-literal fixes (~40 expected)

Known counts from the planning audit: main_menu.gd ×8, game_board.gd ×6,
network_manager.gd ×4, replay_viewer.gd ×4, options.gd ×4, online_play.gd ×3,
extras.gd ×3, loading_screen.gd ×2, deck_builder.gd ×2, public_lobby.gd ×2,
plus session/seat_container, session/board_module, server/headless_board,
lobby scripts, tests. Find them all:

```bash
grep -rn 'res://scenes/ui/\|res://scenes/managers/' . \
  --include='*.gd' --include='*.tscn' --include='*.cfg' --include='*.godot' \
  --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git
```

Fix `.tscn` ext_resource `path=` fallbacks too (uid carries the reference,
but keep text paths correct).

## Grep sweep (zero hits)

Same grep as above → 0; plus `.claude/`, `CLAUDE.md`, `docs/`.

## Docs to write this phase

`scenes/README.md` (presentation map, `FooBar.tscn` ↔ `foo_bar.gd` mirror
convention, domain parity table with scripts/), `scenes/board/README.md`
(absorb/link docs/game-board-architecture.md), `scenes/board/modules/README.md`,
`scenes/board/overlays/README.md`, `scenes/menus/README.md`,
`scenes/lobby/README.md`, `scenes/deck_builder/README.md` (screen-flow
diagrams: which scene navigates where via NetworkManager.change_scene).

## Gate (full + headful)

Scene-change paths fail ONLY at runtime — unit tests will not catch a wrong
`change_scene` string. After the standard gate:

- Headful click-through (use the `verify` skill or play manually):
  main menu → bot game → GameBoard renders; open Options, Extras,
  Deck Builder, LAN lobby, Replay viewer; return to menu from each.

## Commit

`restructure(phase-4): re-slice scenes/ into menus, lobby, deck_builder, replay`
