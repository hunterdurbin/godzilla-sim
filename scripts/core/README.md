# scripts/core/ — pure match engine

Everything here is `RefCounted`, UI-free, and synchronous unless it awaits
player input. Cards are plain `Dictionary`s (templates from `CardData`,
per-copy instance ids like `EBP04-067_0_3` — compare with
`CardUtils.base_id(card)`, never raw `id ==`).

## Files

| File | Role |
|---|---|
| `game_state.gd` | Match-level state container (holds 2 PlayerStates) |
| `player_state.gd` | Per-player state + zone/deck helpers. Zone-occupancy semantics are split: `is_zone_empty`/`get_empty_zone_indices` for placement (the monster zone is never "empty"); `zone_has_battle_card`/`get_battle_card_zone_indices` for "has a battle card" |
| `rules_engine.gd` | Pure validation (`valid_actions`, `validate_action`); depends only on injected `EffectQueries` (`rules_engine.queries`); gates server-side action validation |
| `turn_manager.gd` | Phase state machine; exposes `flow_state` (IDLE / AWAITING_ACTION / PROCESSING_ACTION / ADVANCING_PHASES / GAME_OVER) |
| `match_factory.gd` | Builds + wires a match (`setup` / `setup_from_save`); TurnManager delegates to it |
| `game_events.gd` | Gameplay notification bus — UI/sync/sfx subscribe |
| `actions/` | `ActionHandler` (dispatcher) + resolvers: `play_actions`, `invasion_resolver`, `counter_resolver`, `rule_actions`, `phase_actions` |
| `input/` | PlayerInput decision port: `player_input.gd` (sync defaults), `signal_player_input.gd` (live UI/RPC/bot — re-exposes `choice_requested`, `zone_target_requested`, … + `resolve_*()` callbacks; resolving during the request emit is safe), `scripted_player_input.gd` (queued answers for tests) |

## Contracts

- **Teardown**: every TurnManager owner MUST call `teardown()` when done or
  the cyclic engine graph leaks (verify with headless `--verbose` leak check).
- Engine code awaits `input.*` — base PlayerInput methods are sync,
  SignalPlayerInput overrides are coroutines, so `await input.*` sites carry
  `@warning_ignore("redundant_await")`.
- Rule references in comments (e.g. "rule 10.4.3" for standby resolution)
  point into `comprehensive_rules/`.
