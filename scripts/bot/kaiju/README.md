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
- `kaiju_counter_oracle.gd` — **KaijuCounterOracle**: bridge to
  `scripts/deck_analysis/` (MaxCounterOptimizer) — "max CP still fieldable
  ON TOP of the current board": live monster/zones/unders/strategies passed
  as lock params, the remaining main deck (+hand) as the pool. Own-deck
  CONTENTS are fair knowledge (the bot built the deck); draw ORDER is not
  and is never consulted (multiset entries; the optimizer's
  `deck_order_known` placeholder is where order-awareness would land). This
  is unrelated to `InfoVisibility`, which governs the OPPONENT's hidden
  info. Every run is RNG-fenced like planner deliberation (own salt
  `0x51F0C0DE`), results cached per board/deck composition (cleared per
  turn), and each optimizer gets `teardown()` before the call returns.
  Gated behind `config.kaiju_use_counter_oracle` (kaiju() preset only).
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

## Deck & opponent awareness (v1.2)

- **Deck profile** (`BotDeckProfile.compute`, set on `config.kaiju_deck_profile`
  by `analyze_deck` when `use_planner`): quantifies whether the deck can win
  by invasion — zone-destruction count (the answer to the opponent's zone-8
  blocker), invade-icon density, advances_opponent effects, playstyle scores.
  The evaluator scales `zone_progress`/`zone_diff` down and the counter terms
  up at low viability, and prices `opp_zone8_block` higher when the deck has
  no destruction to clear it.
- **Draw tempo** (`draw_tempo` weight): start-phase draws equal the OPPONENT
  monster's rank (rule 7.2.2) — the term prices the card-economy side of
  rank, so early own rank-ups stop looking like free value.
- **Race counter restraint** (`race_counter_restraint` weight): countering is
  MANDATORY at CP ≥ threat (rule 7.4.3); when both monsters are at zone 6+
  and we lead the race with an invade card in hand, crossing the counter
  threshold is scored net-negative so the beam keeps its deployed CP below
  their threat (deployment restraint) instead of knocking them back,
  re-locking our hand ranks, and gifting them a fresh monster.
- **Forced non-invade finalist**: the best line containing no INVADE always
  joins the opponent-ply re-scoring pass, so "play slow" is ply-tested even
  when invade lines fill the analytic pool.
- **Win-condition proximity** (v1.3.1): advantage is relative and path-based,
  not stat-margin-based. `rankups_diff` prices the LIVES DIFFERENTIAL
  (spending your last rank-up while they hold two is catastrophic even
  though your absolute count dropped by one); `z8_dead_end` recognizes that
  at z7+ with the opponent's zone 8 occupied and no destroys_zone answer in
  hand/board, the invasion win does not exist from that position — camping
  is pure exposure. `cycle_filter` prices the fresh-draw value of a dumped
  hand on non-counter turns.
- **Cycling** (v1.3): when the bot isn't countering this turn anyway
  (`can_counter_opponent()` false), candidate enumeration adds a dump of the
  weakest playable battle card onto its own lowest-CP occupied zone —
  overload (rule 11.5) discards the old card, and the end-phase refill (rule
  7.5.4) converts the play into a fresh draw. Paired with the refill-aware
  `hand_diff` (the evaluator projects our imminent refill to 5, so a dumped
  hand no longer reads as card loss).
- **Opponent next-turn zone projection** (v1.4, `_projected_opp_zone`):
  where their monster will be by the end of THEIR next turn — main-phase
  invade (+`_expected_opp_invade_steps`, gated on both invasion-block
  queries) then the end-phase advance (+1, capped at zone 8); crossing past
  8 (projection 9 = lethal) only while our zone-8 slot is empty. The
  `opp_lethal_penalty` weight fires when projection ≥ 9 and our counter
  doesn't land this leaf — which prices all three outs at once (counter
  them, block zone 8, win first). Projection ≥ 8 ("at the gates") bypasses
  the dead-counter gate, and true lethality (≥ 9) exempts the race-counter
  restraint: survival counters are never suppressed. `zone8_defense` gates
  on the union of the old zone-6 rule and projection ≥ 8 (widening only).
- **Counter ceiling / dead-counter gate** (v1.4, `KaijuCounterOracle`):
  once per match `analyze_deck` stores the deck's unconstrained max-CP
  ceiling on `config.kaiju_deck_counter_ceiling`; each deliberation the planner
  sets `KaijuEvaluator.turn_counter_ceiling` from
  `BotPlayer.max_counter_power_remaining()` (current board locked, deck+hand
  pool). When even that best case can't reach the opponent's threat, the
  evaluator multiplies the counter-pursuit terms (`cp_pressure`,
  `counter_them_bonus`) by the `dead_counter_scale` weight — CP toward an
  unreachable wall stops outbidding the race/board terms. Defensive terms
  (fear of BEING countered) are untouched.
- **Opponent profile** (`KaijuOpponentProfile`, LIVE ONLY — wired by
  game_session, never by the sim runner, keeping headless sims
  seed-deterministic): scans the current version's replays for games against
  this opponent (≥ 3 required), and blends measured tendencies into the
  evaluator with a trust ramp — `cp_per_card` replaces the static
  `opp_cp_growth` prior, `counters_per_turn` scales the defensive terms,
  `invade_tempo`/`early_invader` scale invasion threat.

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
