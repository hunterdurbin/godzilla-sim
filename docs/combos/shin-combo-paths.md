# Shin Combo — Win Paths & Bot Strategy

The Shin Combo is a multi-card win path with two execution paths: a direct self-advance path and a counter-retreat path that punishes opponents who counter.

## Strategy Overview

The shin combo deck plays fundamentally differently from standard decks:
- **No board building** — the deck cycles hand (gains rage) to dig for combo pieces
- **Slow play** — pace-match the opponent, never rush more than 1 zone ahead
- **Counter-retreat is a feature** — getting countered ranks up the monster, potentially triggering "advances_opponent" to crush the opponent's z8 defense
- **Save 2-step invasion cards** — use 1-step for positioning, 2-step only for the win
- **At rank 4, abandon combo** — switch to normal counter/invasion play

## Dual Win Paths

### Path A: Direct Self-Advance
1. Play advance-to-6 card (Card #1) to reach zone 6
2. Play advancement card (Card #2) to reach zone 7+
3. Clear opponent zone 8 if blocked
4. Invade 2-step to win

### Path B: Counter-Retreat (Bonus)
1. Opponent reaches zone 7+
2. Bot invades to zone 6-7, gets countered on purpose
3. Counter-retreat: monster retreats, ranks up to rank 3
4. Rank 3 monster's on_enter advances opponent +1 (z7 to z8), crushing their z8 defense
5. Bot plays advance-to-6 card, then invades 2-step through weakened z8

**Both paths can combine.** The counter-retreat is opportunistic — if the opponent counters, the rank-up bonus fires. If not, the direct path continues.

## Card Roles

| Role | ID | Name | Type | Rank | Effect | Reliability | Extra Cost |
|---|---|---|---|---|---|---|---|
| Card #1 | EBP01-078 | Godzilla Attacks | Strategy | 4 | Advance to zone 6 (guaranteed) | 100% at zone 4+ | None |
| Card #1 | EBP02-014 | Cabinet Helicopter | Battle | 6 | Mill top deck; if monster, advance to zone 6 | ~20-50% (deck monster ratio) | None |
| Card #1 | EBP03-035 | Satsuma | Battle | 5 | Same column as opp monster: discard strategy, advance to zone 6 | 90% (column + strategy) | 1 strategy discard |
| Card #2 | EBP02-003 | Godzilla(2016) 2nd Form | Monster | 2 / Burst 3 | If GUC in stack, discard strategy to advance +1 | 100% | 1 strategy discard |
| Counter-retreat | EBP01-008 | Godzilla(2004) | Monster | 3 | On enter: advance opponent +1 zone | Auto (on rank-up) | None |
| Destroy | (various) | — | Battle/Strategy | Varies | Cards with `destroys_zone` tag | Varies | Varies |
| Invasion | (various) | — | Any | — | Cards with `invasion_icon >= 2` | 100% | Discarded on use |

## Bot Decision Flow

### Deck Compatibility Check
The shin combo only enables if the deck has ALL core pieces:
- `advances_self` card with max_zone >= 7 (advancement)
- `advances_self` card with max_zone >= 6 (advance-to-6)
- Card with `invasion_icon >= 2` (2-step invasion)

The counter-retreat path (rank 3 "advances_opponent" in monster deck) is detected dynamically and enhances the combo when present.

### Tempo Control (Invasion Suppression)

| Condition | Suppressed? | Reason |
|---|---|---|
| Bot 1+ zones ahead of opponent | Yes | Pace-match, don't overextend |
| Bot at z5+, opponent below z7 | Yes | Wait for counter-bait window |
| Opponent at z7+, bot at z5-6 | **No** | Counter-bait — position for counter |
| Full state at z6-7 | **No** | Execution ready |
| 2-step early invasion (INVASION playstyle) | **Suppressed** | Save 2-step cards for win |

### Invasion Zone Caps

| Opponent Zone | Max Invasion Zone | Reason |
|---|---|---|
| z1-6 | opponent_zone + 1 | Pace-match |
| z7+ | z6 | Avoid z7→z8 end-of-turn (suicidal) |
| Any (35k+ threat surplus) | No cap | Overwhelming advantage |

### Execution Gating
The combo execution step only fires when:
- Viability > 0 (combo is actually viable)
- Bot is below z8 (z8+ is past the combo's effective zone)
- Opponent at z6+ OR opponent has a card in z8
- Bot at z6+ when opponent at z7+ (don't advance into danger below z6)

### Card Cycling
In partial state with counter-retreat path available:
- Prioritize gaining rage before playing cards (discard monster → draw at end of turn)
- Protects: invasion card, advancement card, advance-to-6 card from discard
- Strategy protection: -80 score penalty for playing strategies when ≤ 2 remain in hand
- Stop cycling when opponent at z7+ (need to defend)

### Rank-Up Selection
When countered, the bot scores rank-up candidates:
- Base: rank value + threat level
- "advances_opponent" with opponent at z7+: **+200** (crush their z8 defense)
- "advances_opponent" with opponent at z5-6: +50
- "destroys_zone": +20
- "boosts_threat" with rage ≥ 2: +15

### Rank 4 Cutoff
At rank 4+, counter-retreat can no longer reach rank 3. The combo returns empty and the bot switches to normal counter/invasion play.

## Viability Scoring

| Factor | Condition | Score |
|---|---|---|
| Proximity | Zone 3 | +50 |
| Proximity | Zone 4 | +70 |
| Proximity | Zone 5 | +90 |
| Proximity | Zone 6 | +100 |
| Opponent (counter-retreat) | Opp Z7+ with counter-retreat path | +30 |
| Opponent (no CR) | Opp Z1-4 | +20 |
| Opponent (no CR) | Opp Z5-6 | +0 |
| Opponent (no CR) | Opp Z7 | -20 (halved if can counter) |
| Opponent (no CR) | Opp Z8 | -40 (halved if can counter) |
| Z8 clear | No destroy needed | +20 |
| Hand flexibility | 5+ remaining after combo | -5 |
| Hand flexibility | 3-4 remaining | -10 |
| Hand flexibility | 1-2 remaining | -15 |
| Hand flexibility | 0 remaining | -20 |
| CP gap | >= 10000 behind | -30 |
| CP gap | >= 5000 behind | -15 |
| Invasion blocked | Effect blocks own invasion | -100 |

## Monster Play Rules
When advancement is a monster (e.g. EBP02-003):
- **Partial state**: exclude the specific card from normal monster plays. Other monsters can play freely.
- **Full state**: skip all monster plays to preserve rank slot, or force-play the advancement monster if playable.

## Partial State Protections
- **Discard protection**: invasion card, advancement card, advance-to-6 card (via `get_partial_reserved_indices`)
- **Score penalty**: only invasion card gets -100 (prevent playing as battle card)
- **Strategy protection**: -80 when ≤ 2 strategies remain
- **No invasion blocking**: partial state doesn't prevent the bot from invading
