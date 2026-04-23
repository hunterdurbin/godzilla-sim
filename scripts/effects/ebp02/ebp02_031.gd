extends CardEffect

## EBP02-031: MBT-MB92 modified - Battle Rank 4 (Blue)
## You may have any number of this card in your deck.
## If the number of other rank 5 or lower battle cards in your zones is 2 or more,
## this card gains +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]



func get_counter_power_modifier(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	var count: int = ctx.owner.count_zones_matching(
		func(c: Dictionary) -> bool:
			return c.get("id", "") != card_id and ctx.field_rank(c, ctx.owner.player_id) <= 5)
	if count >= 2:
		return 3000
	return 0
