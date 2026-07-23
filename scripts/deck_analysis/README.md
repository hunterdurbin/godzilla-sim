# scripts/deck_analysis/ — decklist analysis on real engine states

Deck-builder analysis that answers questions about a decklist by
**constructing a valid `GameState` and asking the real engine**, never by
hand-summing card fields. Depends on `core/` + `effects/` + `cards/`
(logic layer only, `RefCounted`, UI-free). Two callers: the deck builder
(`scenes/deck_builder/max_counter_dialog.gd`, unconstrained decklist
preview) and the KAIJU bot (`scripts/bot/kaiju/kaiju_counter_oracle.gd`,
live-board-locked "max CP still fieldable" runs).

## Files

| File | Role |
|---|---|
| `max_counter_state.gd` | `MaxCounterState` — synthetic counter-phase board: wires GameState + EffectHandler + ActionHandler (the `tests/fixtures/states.gd make_session` stack, minus GameEvents), `apply(assignment)` / `evaluate()` / `breakdown()` / `teardown()` |
| `max_counter_optimizer.gd` | `MaxCounterOptimizer` — searches board assignments for the deck's maximum counter power; every candidate board is scored via `MaxCounterState.evaluate()` (CounterResolver.compute_counter_numbers) |

## The synthetic state (MaxCounterState)

Player 0 counters on their **own turn** (`current_phase = COUNTER`,
`current_player_id = 0`) — that is the real counter perspective
(TurnManager resolves the counter with the counterer as current player), so
`<Your Turn>` modifiers legitimately count. The opponent board is empty, so
engagement restriction / immunity / prevention no-op.

Best-case assumptions (only *time-decoupled* facts are assumed; anything
queried at counter time must be genuinely true on the constructed board):

- **rage** — searched at 10 (effects can gain rage), re-checked at 0 for the
  winner; the higher board wins. Pinnable via params.
- **monster placement** — any zone 1–8; the monster stack holds the deck's
  lower ranks (normal rank-up), so stack/Awakening conditionals are honest.
  Pinnable via params.
- **opponent monster zone & rank** — `players[1].monster_zone` is set
  (column-conditional cards like EBP02-016 read only the int), and when an
  `opp_monster_rank` is given the opponent gets a synthetic `{rank}` monster
  (rank-conditional cards like ESD02-012 read it; absent = monster-less,
  rank reads as 1). Default: joint best-case sweep over zone × rank; each
  dimension is independently pinnable via params.
- **play-rank legality** — rank requirements are checked at play time
  against positions that reach 8 over a game; always best-case satisfiable.
  Play-ZONE restrictions (`get_required_play_zones`, e.g. EBP04-067 "only
  in zone 8") ARE enforced — stamped per candidate at pool build.
- **discard pile** — every unplaced main-deck copy (late-game best case);
  hand and deck are empty, so deck-count effects read 0

- **strategy zones** — 2 by default; constructed with `strategy_zone_count`
  3 the state grows the zone arrays exactly like EBP03-013's `on_enter`
  (the array size is the engine's source of truth for the zone count).

Assignment keys: `monster`, `monster_zone`, `zones[8]` (one entry per
strategy zone in `strategies`), `rage`, plus optional `opp_monster_zone`
(default 1), `opp_monster_rank` (default 0 = monster-less), `unders`
({zone_idx → card} tucked beneath that zone's top; one under max; buried
cards are data only — their own effects are inactive, and they are consumed
from the pool like any fielded card), and `monster_stack` (a live caller's
REAL stack used verbatim instead of the synthesized best-case one).

`teardown()` is mandatory (breaks the ActionHandler/EffectHandler cycles —
same contract as every engine-stack owner).

## The search (MaxCounterOptimizer)

Drive with `setup(monster_entries, main_entries, params)` (deck-builder-
shaped `{card_number, quantity}` entries) then `step()` until false — each
step is one bounded unit so UI callers can yield between frames — or call
`run(...)` synchronously. `params` (all optional): `monster_zone` 0|1-8,
`opp_monster_zone` 0|1-8, `monster_rank` 0|1-4 (restricts the fielded
monster to that rank; a deck with no monster of the rank fields none),
`opp_monster_rank` 0|1-4 (the synthetic opponent monster's rank),
`rage` -1|0-10 (0/-1 = unconstrained),
`strategy_zone_count` 2|3 (3 = assume EBP03-013's permanent expansion; the
dialog only shows the option — defaulted to 3 — when the monster deck runs
that card, and pins 2 otherwise).

Live-board lock params (the bot's constrained runs; empty = unchanged v1
search): `locked_zones` / `locked_unders` ({zone_idx → card}),
`locked_strategies` ({slot_idx → card}), `locked_monster` (pins the config —
`monster_entries` may then be empty), `monster_stack` (passthrough to
`apply`). Locked cards are fixed occupants: pre-placed by
`_empty_assignment`, skipped by every fill/replace/relocate/tuck/strategy
pass, re-stamped into a `_lk_` id namespace so live instance ids can't
collide with `_expand_entries` ids in `_board_valid`'s uniqueness set.
`locked_zones` must not include `monster_zone - 1` (the crush rule keeps
live boards out of that state). Entries hold only the still-AVAILABLE pool —
locked cards are not also entries. Work bounds: `finalists` (default 3),
`improve_passes` (default 3; 0 = seed only) — the bot passes 1/1 (or /0
when nothing is free). `deck_order_known` is a reserved no-op placeholder:
the pool is a multiset (own-deck contents are inferable, draw order is
not); a future version may weight candidates by draw distance. `result()`
returns `{total_cp, monster, monster_zone, zones[8], strategies[2..3],
zone_cp[8], zone_mods[8], monster_cp_mod, strategy_cp_mods, rage,
opp_monster_zone, opp_monster_rank, unders}` — all numbers read back from
`compute_counter_numbers` / `get_zone_cp_breakdown`.

Shape: (monster × monster_zone) config loop → up to three greedy seeds per
config (solo-score order; effectful-cards-first order so adjacency-
conditional cards win contested monster-adjacent slots against
placement-free bodies; tokens-first order so 0-CP enabler tokens like
EBP02-T03 Crystals can feed threshold strategies like EBP02-072 — the
replace pass trims any excess tokens back down but can't build the pile up
one losing swap at a time), each scored as a full board (unders attached,
strategies picked) with the best kept → top-3 finalists get opp-state sweep
/ replace / relocate / under-attach / strategy improvement passes. The strategy pool keeps up to one copy per
strategy slot per id (identical strategies are legal — one per slot — and
stacking field-CP strategies like EBP04-082 want one each). `_board_valid` rejects any
board fielding the same card instance twice (zones + strategy slots +
unders combined).

**Opponent zone/rank "Any"** is a sweep, not a config multiplier: seeds run
at opp zone 1 / rank 1; each improvement pass first evaluates the finalist
under every unpinned (zone, rank) pair — 8 × 4 with both left Any, either
dimension collapsing to its pinned value — and adopts the best, then the
placement passes optimize under it. A finalist that only shines under a
non-default opp state could in principle miss the top-3 cut — same class
of looseness as the greedy seeds; the lower-bound guarantee holds.

Greedy + swaps is a **lower bound**: any reported board is valid and
engine-verified, never an overstatement.

### TOKEN_SOURCES

Token generators cannot be found statically (~370 effect scripts), so the
optimizer keeps a hand-maintained `TOKEN_SOURCES` map: generator id →
token id + mode (`replace` / `extra` / `fill` / `linked`). The guard test
in `tests/unit/deck_analysis/test_max_counter_optimizer.gd` greps effect
sources for `create_token_in_zone` callers and fails if one is missing from
the map — **add an entry whenever a new set introduces a token generator.**

`replace` tokens (EBP02-077 → T04) also consume a *mill witness*: a card
with the required trait that stays in the deck (never fielded). `_board_valid`
enforces witness counts, generator/token exclusion pairs, `linked` zone
locks (EBP04-067's token lives in zone 3 while its generator survives), and
monster-sourced generators being reachable by the fielded monster's rank.

`fill` tokens (EBP02-020) consume *discard witnesses*: five strategy copies
that stay in the discard (fielding one invalidates the board — the
`__fill_gate` stamp, enforced in `_board_valid`; the played 020 copy may
itself occupy a strategy slot).

Known looseness (documented, acceptable): adjacency of `extra` tokens to
their generator's play zone is not re-checked on the final board.

### STACK_SOURCES

Cards whose CP effects need a card tucked UNDER them (`STACK_SOURCES` map,
same maintenance contract as TOKEN_SOURCES — its guard test keys on CP
triggers + `get_cards_under_top`/`get_zone_stack` reads in effect sources):

- EBP03-064 (tucks any battle card from discard; +3000/+6000 w/ Awakening)
- EBP01-026 (tucks a GIGAN+FEST card from discard at counter start; +5000)
- EBP03-051 (stacks onto a LITTLE_GODZILLA top when played; +5000 per
  under — modeled capped at **one under**, a documented undercount)
- EBP04-043 (tucks an invasion-icon-2 strategy *from a strategy zone* at
  counter start — so strategy-unders + filled strategy slots ≤ 2)
- EPR-016 (tucks a MECH/WEAPON/GODZILLA_THE_RIDE battle card *from hand* at
  counter start; +5000 — modeled like discard: pool card, no slot cost. Its
  end-phase self-destroy is irrelevant here: the counter happens first)

Independent of a top's listed source, an under also qualifies via
**evolution** (`_evolves_under`): a card whose `evolution_rank` /
`evolution_trait` cover the top's rank/traits could legally have had the
top played onto it by `perform_evolution`, so it may sit underneath —
without consuming a strategy slot. (As of EBP04 no stack-source top has a
matching evolution card that its own filter rejects, so this is
future-proofing for narrower filters.)

The attach pass tucks the cheapest eligible card (buried cards contribute
no CP): spares directly; fielded candidates are detached and their zone
backfilled with the best plain spare — the engine arbitrates the whole
trade, kept only on strict improvement. Stack-source tops are also scored
WITH their best under in the solo ranking, and seeds are compared only
after under-attachment — scored bare, a 6000-printed EBP03-064 loses its
slot to a plain 10000 body it beats once the under arrives.

## Tests

`tests/unit/deck_analysis/` — harness contract, search behavior (top-7,
adjacency placement, strategy flat bonuses, token upgrade/witness/fill/
linked cases), a smoke pass evaluating every CP-triggered card on the
synthetic state, and the TOKEN_SOURCES guard.
