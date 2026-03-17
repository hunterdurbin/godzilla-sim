# Bot Decision Paths

How the bot AI (`BotPlayer`) makes decisions each turn during the main phase.

## Main Action Priority (\_decide\_main\_action)

Each main phase action is decided by this priority chain. The bot picks the **first** action that applies:

| Step | Action | Condition | Notes |
|------|--------|-----------|-------|
| 0 | Combo check | Always | Detect multi-card win paths, set combo plan |
| 1 | Play monster | Monster playable, combo doesn't skip | Increases rage/threat. Combo may force/exclude specific monsters |
| 2 | Win invasion | Zone 7+, opponent z8 clear | Top priority — invade to win immediately |
| 2.5 | Combo execution | Combo pieces ready + opponent in position | Forced sequencing: advance-to-6 → advancement → destroy → invade |
| 3 | Early invasion | INVASION playstyle, not combo-suppressed | 2-step aggressive invasion. Skipped when combo prefers 1-step |
| 4 | Combo cycling | Combo needs pieces, opponent below z7 | Gain rage to cycle hand (discard monster → draw at end of turn) |
| 5 | Gain rage | Ahead on CP | Build threat before playing cards |
| 6 | Play best card | Score all playable cards | Strategies and battle cards scored by tags, triggers, CP, synergies |
| 7 | Gain rage (fallback) | Behind on CP | Try rage as fallback when no good cards |
| 8 | Invade | Not behind on CP, not combo-suppressed | Playstyle-dependent: INVASION always, BALANCED at z4+ |
| 9 | Pass | Always | No actions left |

## Card Scoring (\_score\_card + \_decide\_best\_card\_play)

Cards are scored by additive layers:

### Base Score
- `config.base_play_score` (default: 10)

### Trigger Score
- Each trigger the card has (on_enter, get_counter_power_modifier, etc.) adds points from `config.trigger_score_rules`
- Unfulfillable triggers subtract `config.unfulfilled_trigger_penalty`

### Tag Score
- Each bot tag adds its configured value from `config.tag_scores` (e.g. destroys_zone: 30, advances_self: 20)
- Situational bonuses add on top (e.g. destroys_zone +50 when near winning and z8 blocked)

### Battle Card Bonuses
- CP / `config.cp_bonus_divisor` (default: /1000)
- When behind on CP: CP * min(gap, 20000) / 10000 (scales with gap)
- When opponent at z7+: CP / 200 (emergency defense)
- Synergy enabler bonus (if playing this card enables synergies for other cards in hand)

### Combo Adjustments
- Full state: boosted pieces get +max(viability, 100)
- Partial state: invasion card gets -100 (prevent playing as battle card)
- Strategy protection: -80 when <= 2 strategies remain (shin combo)

### Tiebreaker
When scores are equal: lower rank > higher CP > random

## Zone Selection (\_pick\_battle\_zone)

Battle card zone placement follows this priority chain:

| Priority | Condition | Zone Selection |
|----------|-----------|----------------|
| 1 | Card CP > existing card CP | Filter out zones where overwriting would lose CP |
| 2 | Crush zone awareness | Avoid zones monster will advance through (next 2 turns) |
| 3 | Combo zone avoidance | Avoid zones combo will crush during execution |
| 4 | Proactive z8 defense | Opponent at z5+: place in z8 first |
| 5 | Zone-dependent tag | Card's preferred zones (from effect) |
| 6 | Column-dependent tags | Match opponent's monster column, avoid opponent cards, etc. |
| 7 | Early game defense | Opponent z1-4: place behind own monster |
| 8 | Zone priority table | Priority order based on own monster zone |
| 9 | Lowest CP overwrite | If all zones full: overwrite lowest CP card |

## Invasion Decision (\_decide\_invade)

| Check | Condition | Result |
|-------|-----------|--------|
| No cards | No discardable invasion cards | Don't invade |
| Opponent z7+ | Bot below z7 and no counter-retreat path | Don't invade (defend) |
| Counter-bait | Opponent z7+ with counter-retreat path | Allow invasion |
| Combo target | Combo specifies target zone | Try to reach it with preferred steps |
| Combo max | Combo sets max_zone | Don't overshoot |
| INVASION style | Prefer 2-step, then any card | Respect combo max_zone |
| BALANCED style | Conservative: z6→z7, z1→z3, z3→z4, z4→z6 | Respect combo max_zone |
| Rage check | Not enough monsters for rage at z7+ | Block invasion |

## Playstyle Detection (analyze\_deck)

Scanned at game start from all cards in deck + hand:

| Signal | Invasion Weight | Counter Weight |
|--------|----------------|----------------|
| advances_self, boosts_threat | +3 | |
| disrupts_hand, destroys_zone | +2 | |
| invasion_icon > 0 | +1.5 | |
| get_counter_power_modifier | | +3 |
| get_field_cp_modifiers | | +3 |
| blocks_invade, blocks_zone | | +2 |

If invasion_score / total > `playstyle_threshold` (0.6): **INVASION**
If counter_score / total > threshold: **COUNTER**
Otherwise: **BALANCED**

## Rank-Up Selection (\_score\_rankup\_candidates)

When the bot must choose a monster during rank-up (after being countered):

| Layer | Factor | Score |
|-------|--------|-------|
| Base | Monster rank | rank * 10 |
| Base | Threat level | threat / 1000 |
| Tags | advances_opponent + opponent z5+ | +40 |
| Tags | destroys_zone | +20 |
| Tags | boosts_threat + rage >= 2 | +15 |
| Tags | advances_self | +10 |
| Combo | Shin: advances_opponent + opponent z7+ | **+200** |
| Combo | Shin: advances_opponent + opponent z5-6 | +50 |

## Difficulty Presets

| Setting | Easy | Normal | Hard |
|---------|------|--------|------|
| Tag scores | 60% | 100% | 130% |
| Synergies | Disabled | Enabled | 1.5x multiplier |
| Zone priority | Random | Table | Table |
| Early invasion | Disabled | Enabled | Threshold z6 |
| Column logic | Disabled | Enabled | Enabled |
| Activation check | Disabled | Enabled | Enabled (130% penalty) |
| Combos | None | None | ["shin"] |
| Action delay | 0.7s | 0.5s | 0.3s |
