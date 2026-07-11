# scenes/menus/ — app screens

| Scene | Role |
|---|---|
| `LoadingScreen.tscn` | **Main scene** (project.godot `run/main_scene`). Boot: loads settings/locale, then → MainMenu |
| `MainMenu.tscn` | Hub: deck pickers + Solo v Self / Solo v Bot / LAN / Online / Deck Builder / Extras / Options |
| `Options.tscn` | Settings UI over `GameSettings` (locale change reloads via LoadingScreen) |
| `Extras.tscn` | Replays, saves, artwork download, links → ReplayViewer |

## Screen flow (via `NetworkManager.change_scene`)

```
LoadingScreen ─→ MainMenu ─┬─ solo/bot ────────→ scenes/board/GameBoard
                           ├─ LAN ─────────────→ scenes/lobby/LanLobby
                           ├─ Online ──────────→ scenes/lobby/OnlinePlay
                           ├─ Deck Builder ────→ scenes/deck_builder/DeckBuilder
                           ├─ Extras ──────────→ Extras ─→ scenes/replay/ReplayViewer
                           └─ Options ─────────→ Options ─(locale change)→ LoadingScreen
(every screen's Back returns to MainMenu)
```

Deck pickers embed `scenes/deck_builder/DeckSelect.tscn`.

## Gamepad

MainMenu wires an explicit full-screen focus mesh (`_wire_pad_mesh()` in
`main_menu.gd`) instead of default spatial nav — every node declares all four
`focus_neighbor_*` (self-loop at outer edges). Priority routes: P2 deck picker
→ right → Options rail (rail returns left to P2), Solo v Bot → right → gear,
and all three corner buttons (Discord, Patreon, Extras) → Deck Builder. The
graph is asserted edge-for-edge by
`tests/unit/gamepad/test_main_menu_pad.gd::test_full_menu_mesh`.
