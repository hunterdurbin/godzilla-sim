# scenes/board/modules/ — board submodules

Script-only submodules of GameBoard following the **BoardModule pattern**
(`scripts/session/board_module.gd`): each module locates the board/session
via the named "GameBoard" subtree, subscribes to GameEvents / UI signals, and
reads the board's forwarded `_board._x` state.

| Module | Responsibility |
|---|---|
| `selection_controller.gd` | Card/zone selection flows and confirm/cancel state machine; prompt previews are controller-cursor stops (`hint_<i>` registry + `prompt_previews_changed` re-resolve) |
| `hand_controller.gd` | Hand fan layout, sorting, drag interactions |
| `mobile_layout.gd` | Mobile re-layout (reparents action panel etc.) |
| `end_game_controller.gd` | Game-over UI, results, rematch entry |
| `reconnect_controller.gd` | Mid-game reconnect flow |
| `effect_stack_panel.gd` | Pending/active effect display; rows are controller-cursor stops (`stack_<i>` registry + `rows_changed` re-resolve, Select-hint row) |
| `first_player_ui.gd` | First-player decision UI |
| `turn_tracker.gd` | Turn/phase tracker panel |
| `log_chat.gd` | Game log + chat panel |
| `board_sfx.gd` | GameEvents → SfxManager bridge |
| `lobby_bot_controller.gd` | Public-lobby bot fallback: waiting banner, opponent found/disconnected dialogs, countdown |
| `card_zoom_controller.gd` | Card zoom overlay + hover/long-press previews, zoom-source inference |
| `effect_highlight_controller.gd` | Effect-driven zone/card highlights + card-attention pulse |
| `board_layout_controller.gd` | Desktop layout: local-player mirroring, hand positioning, button stacks, hand collapse |
| `system_menu_controller.gd` | Sound/music toggles, bug report, log export, save button, concede/main-menu |
| `board_nav_graph.gd` | Builds the ONE controller-navigation graph (playmat + hand + buttons + log + tracker + choice + stack + prompt-preview hint nodes); edit its tables to change cursor travel — see `scripts/input/README.md` |
| `gamepad_board_nav.gd` | Controller cursor over that graph: prompt landing/validity gating (hand/choice/confirm prompts jail movement; zone & strategy targeting free-roam the whole board), bumper focus (LB log / RB tracker), Select toggle (effects area ↔ board, read-only roam during a choice: viewers open, plays gated), post-play return, the null-focus invariant |
| `nav_debug_overlay.gd` | F3 (debug builds) live nav-graph visualization; `editor_preview` renders the static tables over GameBoard.tscn in the editor |
| `hand_hint_bar.gd` | Bottom-left glyph hints (A play / LT rage / RT invade) while the pad cursor free-browses a hand card on the local player's action; rows filtered per card via `SelectionController.hand_card_hint_actions()` |

Rematch negotiation lives in `end_game_controller.gd`; the board-wide
rematch reset (`_execute_rematch`) intentionally stays on game_board.gd —
it touches state owned across modules.

## Extraction lessons (Phase 8 — read before extracting more)

Moved bodies run on the MODULE node, so anything implicitly bound to the
board must be redirected: bare `$Path` → `_board.get_node("Path")`,
`add_child(x)` → `_board.add_child(x)`, `reparent(self)` →
`reparent(_board)`, `self` passed as "the board" → `_board`. The unit suite
and multiplayer harness do NOT execute the real GameBoard's `_ready` (they
use stub/headless boards) — only a headful run catches these.

## Adding a module

1. Create `snake_case.gd` here extending the BoardModule base.
2. Wire it in GameBoard.tscn under the module container node.
3. Read board state via forwarded fields (add a forwarding property on
   game_board.gd if missing); never duplicate state.
4. If the session layer must call it, add a **thin delegate on
   game_board.gd** instead of exposing the module — the stub/headless boards
   must stay in lockstep (see `scripts/session/README.md`).
