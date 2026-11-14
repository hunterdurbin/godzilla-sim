# scripts/effects/ — the card-effect system

⚠️ **This directory is PATH-FROZEN.** The card set files (`scripts/cards/sets/`) embed ~368
`"effect_script": "res://scripts/effects/…"` strings and the generated
`trigger_map.gd` embeds the same set; EffectRegistry loads by these strings
and the pre-commit hook / codegen reference this path. Never move or rename
files here without regenerating everything and migrating card data.

## Architecture

`effect_handler.gd` is the **card-script interface** — a facade whose
public methods are exactly the primitives the per-card scripts
(`scripts/effects/<set>/`) call through `ctx.effect_handler`. The
implementation lives in the modules below. `EffectHandler.setup` wires each
one once (`EffectModule.wire`) with direct references to the others, so a
module calls another module directly (`dispatcher.collect_enter_entries`,
`queries.should_stack_on_play`); it uses the facade `h` only for what the
facade itself owns — its signals (`log_message`, `card_evolved`, …) and the
player-prompt primitives with their UI state (`select_zone_target`,
`select_choice`, `reveal_cards`, …).

Everything outside the card scripts — core resolvers and TurnManager, the
board UI, the bot, tests — calls the modules too (`effect_handler.queries`,
`.dispatcher`, `.check_timing`, `.destruction`, `.mover`, `.monster_mover`,
`.enter_zone`, `.registry`; the `ActionResolver` base forwards them). A
facade method that no card script calls doesn't belong on the facade:
`scripts/tools/check_effect_handler_card_api.py` (pre-commit + CI ratchet)
fails on a public EffectHandler method with no caller under
`scripts/effects/<set>/`.

| Module | Role |
|---|---|
| `effect_registry.gd` | Effect/filter loading + caching (test injection point) |
| `trigger_filters.gd` | Pure static `TRIGGER_FILTERS` DSL evaluation |
| `check_timing.gd` | `CheckTiming`: single owner of check timing (10.4.3) — rule actions (crush, illegal cards), the standby pool, the active ability (`get_active_effect_summary`), `run_effect`, `note_effect_resolving` |
| `standby_entry.gd` | `StandbyEntry`: one ability in standby (player, card, callback, `still_applies`) |
| `trigger_dispatcher.gd` | `trigger_*` / `collect_*` dispatch over active cards (`trigger_*` = collect + `check_timing.submit`), `apply_rage_reset` |
| `destruction_engine.gd` | The one destroy operation, `destroy(target, zone, cause)` — cause EFFECT / CRUSH / OVERLOAD decides protection (effect only), replacement (all) and <Revenge> (not Overload); on_destroy and the destroyed watchers fire for all three; returns the StandbyEntry list. Also the effect-driven destroy prompts and strategy destruction |
| `enter_zone.gd` | `EnterZone`: the one "card enters a zone" operation, `enter(player_id, card, zone, source)` — source HAND (the Play action or an effect) / DECK / DISCARD / TOKEN / EVOLUTION; `move_stack` for a stack moving between zones. Owns rule legality (`is_rule_legal`, also asked by RulesEngine, which keeps cost legality), stack-on-play or Overload, placement + signals + log, and submits the leave-play, <Enter> and "when played" entries together |
| `card_mover.gd` | Hand/deck/discard traffic, zone prompts, token instances; its play primitives call `EnterZone` |
| `monster_mover.gd` | Monster movement: the sole writer of `monster_zone` during play (advance with `from_invasion`, retreat, teleport, counter retreat) + the effect-facing move entry points |
| `effect_queries.gd` | Read-only modifier/blocking aggregation (injected into RulesEngine) |

Facade delegate rule: a delegate containing `await` becomes a coroutine —
keep query delegates sync. When calling the facade dynamically, hoist
a typed var first (`var handler: EffectHandler = s["effect_handler"]`) —
typed-array params + dynamic calls can silently abort coroutines.

## Per-card scripts

One script per card in per-set dirs (`ebp01/`–`ebp04/`, `esd01/`–`esd05/`,
`esc01/`, `efc01/`, `epr/`), named by card id (`ebp04_090.gd`). Each extends
the CardEffect base and overrides trigger virtuals; awakening effects key off
**monster_zone** (`AwakeningN` = `monster_zone >= N`), not rage.
Which cards override a hook, with their text and rulings:
`python3 scripts/tools/cards_with_hook.py <hook>`.
`<Dominate>` effects gate on `ctx.is_dominate()` — active while your
monster is in the same zone as, or ahead of, the opponent's monster.

**Card scripts express intent; the engine enforces the rules.** A card script
should read like its card text: "move my monster to zone 8", "play this card
into zone 8", "destroy that card". It calls an EffectHandler primitive for
that intent, and the primitive applies every rule that follows from it:
crush, overload, play-zone legality, replacement effects, Revenge and other
automatic abilities entering standby. Card scripts never mutate zones or the
monster's position directly (`clear_zone`, `push_zone_card`,
`banish_or_discard`, assigning `monster_zone`), and never fire trigger bodies
by hand. If no primitive fits, add one to the engine instead of hand-coding
the rule in the card, so every card gets the rule the same way. Hand-coded
rule logic in a card script is where rules bugs come from.
`scripts/tools/check_card_mutations.py` (pre-commit + CI) holds the line,
with no allow-list: it fails on zone / monster-position mutation
(`clear_zone(` / `push_zone_card(` / `banish_or_discard(`, assigning
`monster_zone`, writing `zones[...]`) and on writes to `hand` /
`discard_pile` / `main_deck` / `monster_deck` / `strategy_zones`. Add the
missing primitive instead.

Primitives for the common intents (all on EffectHandler):

| Card text | Primitive |
|---|---|
| "<Destroy> this card / that card" | `destroy_zones` (+ the `destroy_zone_target(s)` prompt variants) |
| "play ... from your discard pile / hand / deck" (overloads, fires <Enter>) | `play_from_discard`, `play_battle_card_from_hand`, `play_battle_card_from_deck` (`stack_on_top` for "play it on top of") |
| "choose a card in your hand" (card stays put) / take it / discard it | `choose_hand_card` / `take_hand_card` / `select_hand_card` |
| "move this card / a battle card to a zone" | `move_zone_stack` (overloads), `swap_zones` |
| "place <card> under this card" | `place_card_under_zone` |
| "place <cards> from your discard pile / monster deck under your monster card" | `place_cards_under_monster` |
| "add <card> to your hand" / "return it from your discard pile to your hand" | `add_card_to_hand(s)` / `return_discard_to_hand` (fires on_card_returned_from_discard) |
| "send it to your discard pile" (already removed from deck/hand) / "discard your (entire) hand" | `discard_cards` / `discard_hand_to(pid, 0)` (fires discard-from-hand triggers) |
| "look at the top N cards, put any number on top in any order, send the rest to your discard pile" | `arrange_deck_top` |
| "reveal the top N cards of your deck" (the card's own select prompt shows them) / with a reveal overlay | `take_deck_top` / `reveal_deck_top` |
| "return the rest to your deck and shuffle it" / "then shuffle your deck" | `shuffle_cards_into_deck` |
| "put this card under <card> in your zones" | `move_zone_card_under_zone` |
| "add all cards under this card to your hand" | `return_cards_under_top_to_hand` (sync — safe in replacement hooks) |
| "play / put into play / place … and activate a strategy card" (from deck, discard or hand; 5.9.1 activate = play) | `play_strategy_from_effect` |
| "place a card from your strategy zone under <card>" | `move_strategy_card_under_zone` |
| "you have N strategy zones" | `ensure_strategy_zone_count` |
| "move your monster" | `advance_monster_to_zone`, `retreat_monster_to_zone`, `teleport_monster` |

`scripts/tools/check_card_monster_zone_checks.py` (pre-commit + CI) holds
the line for play-zone legality: card scripts get legal zones from the
engine instead of comparing against the monster's zone index.

## Check timing — automatic abilities never interrupt an effect

Terms per `GLOSSARY.md`. `CheckTiming` (`effect_handler.check_timing`; `check_timing` in the modules) owns all of it.
Engine code runs an ability through `check_timing.run_effect(owner, card,
callback)`: it marks the ability active (read-only `active_player_id` /
`active_card`), announces it (`note_effect_resolving`) and restores the
outer ability afterwards. Trigger sources only **submit**
(`check_timing.submit(entries)`, synchronous): nothing resolves on the spot.
Entries resolve at the next check timing (rule 10.4.3) — `check_timing.resolve()`
after the current action or phase step (the TurnManager sites, 10.4.4.1 /
7.x), or between two abilities of a running pass. So one play's leave-play,
<Enter> and "when played" entries share one pool, the turn player picks
first, and rule actions (crush) run before any of them. Per 10.6.7 an entry
resolves even after its card changed areas (crushed, evolved over,
discarded); the only way one is dropped is its `still_applies` gate
(10.6.3.2). Code that drives the engine outside TurnManager (tests, bot
rollouts) calls `check_timing.resolve()` itself after the action. Only the
dispatcher's `collect_*` functions build `StandbyEntry` objects
(`scripts/tools/check_standby_entry_builders.py`). Never call a
trigger body directly from engine code.
This covers revenge and zone-card-destroyed watchers (single AND batch
destroys, Crush and Overload), on_discard_from_hand, and the area-changing hooks on_leave_play /
on_zone_changed (EBP04-067 link). One exception: an effect destroy resolves
the destroyed card's own `on_destroy` on the spot (`_destroy_by_effect`),
because queueing it would make `destroy_zones` a non-coroutine and trip
REDUNDANT_AWAIT at its ~100 awaiting call sites; Crush and Overload queue it.
**Replacement effects**
(`on_would_be_destroyed`, `can_be_destroyed`) are the exception: they resolve
at the moment of the action. An area-changing entry that has nothing left to
do when it comes up is dropped before the order prompt via
`area_change_still_applies` (10.6.3).

**Crush has one path.** `CheckTiming.check_crush_rule(triggered)`
performs the crush (replacement effects apply at that moment) and only
*collects* the crushed card's leave-play, crush and <Revenge> entries; the
caller submits them to standby once its move / check timing is done
(`check_timing.resolve()`, monster movement, invasion, `teleport_monster` —
which crushes only its destination, e.g. EBP03-068 Godzilla Flies — and the
counter retreat, which crushes before the new monster's <Enter>).

**Play-zone legality is enforced by the play primitives** (5.11.1.1),
through `EnterZone` — the one owner of rule legality (`EnterZone.rule_legal_zones`).
Every play (JA 出現: the Play action, effect plays from hand / deck /
discard, tokens and Evolve) refuses the monster zone and a zone the
opponent blocks (EBP02-055, Q270), stacks a stack-on-play card (Godzilla
Jr.), and fires the "when played" watchers — Evolve as a play from the deck
(Q176). Only the Play action also applies the card's required zones.
`play_battle_card_from_hand` / `_from_deck`, `play_from_discard` and
`create_token_in_zone` refuse an illegal zone and report "not
played" (`false` / `-1`) and the card stays in its area — hand, discard,
or (for a deck card the caller already took out) back on the deck bottom. Card scripts that offer a fixed
zone gate the offer on `can_play_in_zone(player_id, zone_idx)` (EBP04-077)
and never compare against `monster_zone` themselves.

**Standby is one pool** (`CheckTiming.submit` queues; `CheckTiming.resolve`
runs the pass). Before every ability: rule actions, then merge everything
that entered standby meanwhile, then the turn player picks one of ALL their
entries — or, if they have none, the non-turn player picks one of theirs
(10.4.3.1–10.4.3.4). A turn-player ability triggered mid-way through the
non-turn player's abilities therefore resolves next.

## Conditional phase-start triggers — `phase_start_applies`

Every card whose `TRIGGER_FILTERS` pass at a phase start enters the standby
batch — the Pending Effects list and (with 2+ entries) the 10.6.3.1
order-choice prompt. The optional collection-time gate

```gdscript
func phase_start_applies(ctx: EffectContext, phase: CardEnums.GamePhase) -> bool
```

(consulted in `trigger_dispatcher._collect_phase_entries`; `false` = the
card never enqueues) exists for exactly ONE narrow class, and the default
is to NOT use it:

- **Do not gate ordinary conditions** (awakening, board-state "if"
  clauses, target availability). Conditions are checked in the body at
  RESOLUTION time on purpose: an earlier pending effect in the same batch
  can make them true — e.g. a monster advanced into zone 4+ by another
  standby effect must still get its Awakening4 ability that same phase
  start. A collection-gated card would never have entered the batch, so
  gating changes gameplay, not just UI.
- **Gate ONLY armed delayed triggers** — "If you do[, then] … at the
  beginning of <phase>" abilities whose arming event is completed and
  CANNOT occur during the current batch. Examples: `epr_016.gd` (armed by
  its own counter-phase placement, recorded as a turn-stamped per-copy
  flag on the card dict) and `ebp01_012.gd` ("if this card invaded this
  turn" — `has_invaded_this_turn` is set only by the main-phase invade
  action, never by effects). An unarmed copy's trigger does not exist, so
  it must not appear in Pending Effects.
- When you do gate: read PUBLIC state only (the pending list is visible to
  both players — hand/deck contents would leak), and keep the body
  re-check.
- The virtual is direct-called (like `serialize_state`): do NOT add it to
  `generate_trigger_map.sh` METHODS — it is exempted in
  `test_effect_smoke.gd` `METHODS_EXEMPT_NAMES`.

## Codegen — trigger_map.gd

`trigger_map.gd` is GENERATED by `generate_trigger_map.sh` (the pre-commit
hook in `githooks/` regenerates it when this dir changes). Rules:

- **NEVER run the script while a headless game/harness is running** — it
  rewrites trigger_map.gd mid-load.
- Adding a new CardEffect virtual? Add it to `METHODS` in
  `generate_trigger_map.sh` too.
- The unit-test smoke suite (`tests/unit/effects/cards/`) FAILS if
  trigger_map.gd is stale — that's the currency gate.

## Testing

Every effect script is covered in `tests/unit/effects/cards/` (smoke +
cluster + bespoke suites; membership ledger in `classification.md` there).
Real card dicts come from `tests/fixtures/real_cards.gd`
(`Real.instance(id)`) — never raw CardData templates. New/changed card
effects require updated tests.
