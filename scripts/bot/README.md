# scripts/bot/ — bot AI

## Files

| File | Role |
|---|---|
| `bot_player.gd` | `BotPlayer` — the decision brain. Subscribes to the same `SignalPlayerInput` request signals a human UI uses and resolves them (`_on_*` handlers), orchestrates main-phase action choice, owns combo integration. Delegates detail work to the helpers below |
| `bot_scoring.gd` | Card/trigger/synergy scoring, rank-up + choice-option scoring, card sort/pick utilities |
| `bot_zone_picker.gd` | Battle-zone priority and own/opponent zone-target picking |
| `bot_invasion.gd` | Invade decisions: which card, when blocked by rage/cost, best/worst invade picks |
| `bot_selections.gd` | Discard-index and evolution-card picking |
| `bot_config.gd` | `BotConfig` — difficulty presets (`Difficulty` enum) and tuning knobs |
| `bot_combo.gd` | Combo planning base (multi-turn play sequences) |
| `bot_combo_shin.gd` | The Shin counter-retreat setup combo (see `docs/combos/shin-combo-paths.md`) |

## How decisions flow

The bot is just another `PlayerInput` consumer: the engine emits
`choice_requested` / `zone_target_requested` / … on `SignalPlayerInput`, the
bot computes an answer and calls the matching `resolve_*()`. Main-phase
action choice runs through card scoring (`_score_card` + trigger/synergy
bonuses), invasion decisions, and zone priority; combos override greedy
choices when a plan is viable. Decision-path diagrams:
`docs/bot-decisioning-paths/`.

Helper pattern: each helper is `RefCounted` holding a **weakref**-backed
`_bot: BotPlayer` property (a strong back-ref would form an uncollectable
RefCounted cycle with the bot's strong ref to the helper). Method bodies were
moved verbatim; `bot_player.gd` keeps one-line delegates, so every call site
— and therefore the global-RNG call order — is unchanged.

## Behavioral invariants

- Bot code consumes the **global RNG** (sim seeds it per game). Refactors
  must preserve RNG call order or seed-matched runs diverge.
- "Forced" optional triggers in sim output are usually the choice scorer, not
  an effect bug: Skip scores 0 in `_score_choice_options`, so action options
  with unmodeled costs always win.

## Verifying bot changes

Seed-matched behavioral diff via `tests/sim/` (see its README): pin
`base_seed`, run 50 games before/after, diff `[SimResult]` lines. Intentional
behavior changes show as diffs to review; refactors must diff empty.
Unit coverage: `tests/unit/test_bot_*.gd`.
