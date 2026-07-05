# scenes/board/modules/ — board submodules

Script-only submodules of GameBoard following the **BoardModule pattern**
(`scripts/session/board_module.gd`): each module locates the board/session
via the named "GameBoard" subtree, subscribes to GameEvents / UI signals, and
reads the board's forwarded `_board._x` state.

| Module | Responsibility |
|---|---|
| `selection_controller.gd` | Card/zone selection flows and confirm/cancel state machine |
| `hand_controller.gd` | Hand fan layout, sorting, drag interactions |
| `mobile_layout.gd` | Mobile re-layout (reparents action panel etc.) |
| `end_game_controller.gd` | Game-over UI, results, rematch entry |
| `reconnect_controller.gd` | Mid-game reconnect flow |
| `effect_stack_panel.gd` | Pending/active effect display |
| `first_player_ui.gd` | First-player decision UI |
| `turn_tracker.gd` | Turn/phase tracker panel |
| `log_chat.gd` | Game log + chat panel |
| `board_sfx.gd` | GameEvents → SfxManager bridge |

(Phase 8 of `docs/restructure/` will add: rematch, lobby-bot, card-zoom,
effect-highlight, board-layout, and system-menu controllers.)

## Adding a module

1. Create `snake_case.gd` here extending the BoardModule base.
2. Wire it in GameBoard.tscn under the module container node.
3. Read board state via forwarded fields (add a forwarding property on
   game_board.gd if missing); never duplicate state.
4. If the session layer must call it, add a **thin delegate on
   game_board.gd** instead of exposing the module — the stub/headless boards
   must stay in lockstep (see `scripts/session/README.md`).
