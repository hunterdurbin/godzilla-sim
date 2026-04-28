extends CardEffect
## EBP04-023: Godzilla Telestorius - Monster Rank 3 (Green)
## For each of your opponent's battle cards in the same column as this card,
## this card gains +10,000 threat.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "column_dependent_monster_self"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	return ctx.get_opponent_column_zones_with_cards(ctx.owner.monster_zone - 1).size() * 10000
