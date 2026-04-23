extends CardEffect
## EBP04-023: Godzilla Telestorius - Monster Rank 3 (Green)
## For each of your opponent's battle cards in the same column as this card,
## this card gains +10,000 threat.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "column_dependent_monster_self"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)
	var count: int = 0
	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			count += 1
	return count * 10000
