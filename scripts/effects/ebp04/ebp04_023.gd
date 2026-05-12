extends CardEffect
## EBP04-023: Godzilla Telestorius - Monster Rank 3 (Green)
## This card gains +10,000 threat level for each battle card your opponent has in the
## same column as this card.
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
