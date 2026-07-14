# Phase 8 — Split god file #3: game_board.gd (~3,270 lines)

**Goal:** continue extracting GameBoard into `scenes/board/modules/`
controllers. Highest-risk phase — multiplayer contract — so it runs LAST.

## The contract rule (read before touching anything)

`scripts/session/multiplayer_sync.gd` (sole owner of all 47 `@rpc`s) and
other session modules call `_board._rpc_*` / `_board._on_*` / read
`_board._x` fields, duck-typed across THREE implementations:

1. `scenes/board/game_board.gd`
2. `tests/harness/stub_client_board.gd`
3. `scripts/server/headless_board.gd`

**Every method/field the session layer touches stays on game_board.gd** — as
a thin delegate into the new module where needed. Verify before AND after
each extraction:

```bash
grep -n '_board\.' scripts/session/*.gd | sort > /tmp/board_contract_{pre,post}.txt
diff /tmp/board_contract_pre.txt /tmp/board_contract_post.txt   # must be empty
```

No `@rpc` signature changes anywhere in this phase.

## Extraction idiom (existing pattern — copy it)

`scenes/board/modules/` already holds 11 modules using the BoardModule
pattern: modules find the board via the named "GameBoard" subtree, read
`_board._x` forwarding properties, and game_board.gd keeps thin delegates.
Mirror an existing module (e.g. selection_controller.gd) for wiring.
Known gotcha: polymorphic `_board.*` fields need
`@warning_ignore("unused_private_class_variable")` per class.

## Sub-commits (one module each, harness-gated)

| # | New module | Scope (~lines) |
|---|---|---|
| 8a | `modules/rematch_controller.gd` | `_on_rematch_pressed`, `_execute_rematch`, `_setup/populate_rematch_deck_select`, bodies of `_rpc_rematch_*` (~200) |
| 8b | `modules/lobby_bot_controller.gd` | `_setup_lobby_bot_ui`, lobby banner tick/label/return, opponent-found dialog/timer/countdown, `_disconnect_lobby_bot_signals` (~250) |
| 8c | `modules/card_zoom_controller.gd` | `_show_card_zoom`, `_zoom_*`, `_on_card_zoom_hidden`, `_show_card_preview`/`_show_normal_preview`/`_show_strategy_preview`/`_hide_card_preview`, long-press zoom (~350) |
| 8d | `modules/effect_highlight_controller.gd` | `_on_effect_zone/card_(un)highlighted`, `_apply_*_highlight`, `set_card_attention`, `_clear_card_attention`, `_resolve_attention_card`; `_rpc_effect_*` stay as delegates (~200) |
| 8e | `modules/board_layout_controller.gd` | `_arrange_for_local_player`, `_position_hands`, `_fit_button_text`, `_apply_desktop_hand_button_stacks`, hand collapse/restore (mobile_layout.gd stays separate) (~300) |
| 8f | `modules/system_menu_controller.gd` | sound/music toggles, bug report, export log, save button, concede/main-menu handlers (~150) |

Method lists are from the planning audit — reconcile against the live file
first; anything ambiguous stays on game_board.gd. Target: game_board.gd
~3,270 → ~1,400 (orchestration, RPC delegates, action buttons, sync, input
routing).

## Per-sub-commit procedure

1. Contract snapshot (grep above). 2. Extract one module. 3. Contract diff
empty. 4. Unit tests. 5. Harness `./tests/harness/run_harness.sh 3 <godot>`
— no DESYNC/SCRIPT ERROR. 6. Headful spot-check of the touched surface
(8a: finish a bot game → rematch; 8c: hover-zoom a card; 8d: play a card
with an effect highlight; 8e: resize window; 8f: toggle sound). 7. STATE.md.
8. Commit `restructure(phase-8<x>): extract <module>`.

Hazards from project memory: reparenting cards with hover tweens (kill tween
+ reset scale first); badges hide not queue_free(); zone card ids are
per-copy instance ids (`CardUtils.base_id`).

## Phase-end gate

Full standard gate including pinned-seed sim diff; update
`scenes/board/modules/README.md` per extraction.
