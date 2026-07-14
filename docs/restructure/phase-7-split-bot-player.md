# Phase 7 — Split god file #2: bot_player.gd (~2,150 lines)

**Goal:** decompose bot AI into focused helpers with ZERO behavior change,
proven by byte-identical seed-matched sim output.

## The hard constraint

BotPlayer decisions consume the **global RNG** (the sim seeds it per game).
Any change to the ORDER of RNG-consuming calls silently changes behavior.
Therefore: verbatim body moves, identical call order, no early-outs added,
no loop reordering, no "cleanup". The sim diff is a HARD gate: `[SimResult]`
lines byte-identical to `baselines/sim_baseline.txt` after every sub-commit.

## Target decomposition (all in `scripts/bot/`)

Helpers are `RefCounted`, constructed by BotPlayer, holding a back-reference
to the bot (so moved bodies can keep reading `_player`/`_config` state via
the bot). Method bodies move verbatim; call sites become `_scoring.foo(...)`.

| Sub-commit | New file | Moves (grep exact names in bot_player.gd first — list from planning audit) |
|---|---|---|
| 7a | `bot_scoring.gd` | `_score_card`, `_score_from_triggers`, `_score_synergies`, `_score_enabler_bonus`, `_score_rankup_candidates`, `_score_choice_options`, `_card_sort_value`, `_pick_best_card`, `_sort_cards_by_value` |
| 7b | `bot_zone_picker.gd` | `_pick_battle_zone`, `_get_zone_priority`, `_get_crush_zone_indices`, `_pick_zone_choice`, `_pick_opponent_zone_target`, `_pick_own_zone_target`, `_is_valid_destroy_target` |
| 7c | `bot_invasion.gd` | `_decide_invade`, `_invasion_blocked_by_rage`, `_count_invade_cards_with_steps`, `_find_worst_invade_card`, `_find_best_invade_card`, `_is_invade1_cost_blocked`, `_is_last_two_step_card` |
| 7d | `bot_selections.gd` | `_pick_discard_indices`, `_pick_evolution_card`, deck-search / arrange / card-select / hand-selection decision bodies (the `_on_*` signal handlers STAY on BotPlayer as thin delegates) |

Stays on `bot_player.gd` (~600 lines): `class_name BotPlayer`, public surface
(`init_combos`, `analyze_deck`, `is_bot_turn`, `get_cp_gap`,
`can_counter_opponent`, `find_invade_card_with_steps`), all `_on_*` handlers,
combo integration (`_get_combo_*`, `_ensure_combo_plan`, `_combo_log_state`)
— bot_combo.gd / bot_combo_shin.gd are already separate files.

Adjust method lists to reality — the file may have drifted since the audit.
Anything ambiguous stays on BotPlayer (moving less is always safe).

## Per-sub-commit procedure

1. Extract ONE helper. 2. Unit tests (`test_bot_choice_scoring`,
`test_bot_invade_decision`, full suite). 3. Pinned-seed sim →
`[SimResult]` diff vs baseline → must be EMPTY. 4. Revert seed pin.
5. Record in STATE.md. 6. Commit `restructure(phase-7<x>): extract <helper>`.
If the diff is non-empty: `git checkout` the extraction, retry smaller.

## Docs

Finalize `scripts/bot/README.md`: decision pipeline
(decide_main_action → scoring → zone/invasion/selection → combos), file map,
the sim-diff procedure, link to docs/bot-decisioning-paths/.

## Gate

Per sub-commit as above; full standard gate (incl. harness) once at phase end.
