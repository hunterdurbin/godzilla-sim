# scripts/bot/kaiju/ — KAIJU-tier turn-plan search

The KAIJU difficulty replaces the greedy priority ladder with lookahead:
enumerate action *sequences* for the bot's own turn on a cloned scratch
match, score the end-of-turn states, pick the best line. Gated entirely
behind `BotConfig.use_planner` — EASY/NORMAL/HARD never enter this code, so
their global-RNG call order (and seed-matched sim diffs) are untouched.

## Modules

- `kaiju_rollout.gd` — **KaijuRollout**: one scratch TurnManager built from a
  `GameSerializer` snapshot via `MatchFactory.setup_from_save`.
  `apply(action, params)` executes real engine actions (mirrors
  `TurnManager.submit_action`'s execute → check-timing → win-check sequence).
  `determinize()` hides the opponent's hand/deck order per the
  info-visibility knob. **Every rollout must get `release()`** — the scratch
  TurnManager is a cyclic graph (match-teardown contract).
- `kaiju_rollout_input.gd` — **KaijuRolloutInput**: synchronous PlayerInput
  answering mid-effect sub-decisions inside rollouts. Planner-side decisions
  delegate to a throwaway "policy" BotPlayer's heuristics (same scorers the
  live `_on_*` handlers use); opponent-side decisions use base defaults.
  Signatures are byte-identical to `PlayerInput` — a typed-array mismatch on
  a dynamically awaited call aborts the engine coroutine silently.
- `kaiju_evaluator.gd` — **KaijuEvaluator**: weighted feature sum over an
  end-of-turn state. Weights come from `BotConfig.kaiju_eval_weights`, keyed
  by game phase. Counter/End phases are folded in analytically (mirrors
  `CounterResolver.compute_counter_numbers`); fragile CP from strategy-zone
  sources is discounted via the `modifier_breakdown` data.
- `kaiju_planner.gd` — **KaijuPlanner**: beam search + per-turn plan cache,
  hooked from `BotPlayer._on_awaiting_action` when `config.use_planner`.
  When `config.kaiju_opponent_ply` is on, the top `kaiju_finalists` end-of-
  turn lines are re-scored by actually playing the turn boundary + a greedy
  opponent reply on the scratch match (`KaijuRollout.play_opponent_reply`) —
  this sees one-turn opponent CP spikes and lethal counter setups that the
  analytic leaf model (`opp_cp_growth`-based) structurally cannot.

## Phases (early/mid/late)

`KaijuEvaluator.phase_key` latches on the game's high-water mark: once the
max monster zone either player has *ever* reached crosses a threshold (or a
turn threshold passes), the phase never regresses — monsters retreat when
countered, but the game stays "late". The planner maintains the max-zone
latch across the match; `invasion_zones_crossed` on PlayerState is per-turn
and NOT usable for this.

## RNG fence

Rollouts unavoidably consume the global RNG (deck reshuffles,
`card_mover.gd` shuffles, heuristic tiebreaks), and Godot 4 has no way to
read the global RNG state back. So the planner re-seeds deterministically:
`seed(hash([state_hash, turn_number, "kaiju"]))` before deliberation and a
derived value after. Consequences:

- Other tiers' RNG streams are untouched (they never reach this code).
- KAIJU games are fully deterministic per `base_seed` — two identical runs
  diff empty — but KAIJU results are NOT comparable against HARD baselines.

## Debugging

Set `KAIJU_DEBUG=1` in the environment to print each deliberation: the root
candidate list with opponent-CP/threat numbers, per-candidate depth-1 scores,
the chosen plan, and cache hits/divergences.

## Known v1 limitations

- ~~Turn-scoped "until end of turn" effect state is not serialized~~ FIXED:
  `CardEffect.serialize_state`/`restore_state` round-trip effect member state
  through `GameSerializer.serialize_player_state(ps, effect_handler)` →
  `MatchFactory.setup_from_save` (`effect_state` sub-dict, keyed by card
  instance id). Stateful effect scripts must override both hooks.
- ~~Mid-effect choices in the LIVE game still use the heuristic `_on_*`
  handlers~~ FIXED: the rollout input records every planner-side answer
  (`KaijuRolloutInput.decision_log`, per-apply), the planner stores them on
  each plan step (`sub_decisions`), and the live bot replays them through a
  scripted-answer queue (`BotPlayer._pop_scripted`) with per-prompt
  validation; any mismatch falls back to the heuristics and the hash check
  replans.
- ~~Combo plans are not consulted for main actions~~ FIXED: candidate
  enumeration runs combo detection on the rollout's policy bot, injects the
  combo's `get_execution_action` as the leading candidate, keeps reserved
  pieces out of the rage/invade/battle/strategy pools, and the evaluator's
  `combo_progress` feature (weights in `kaiju_eval_weights.*.combo_progress`)
  rewards assembling the line.
