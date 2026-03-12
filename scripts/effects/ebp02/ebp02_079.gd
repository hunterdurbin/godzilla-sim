extends CardEffect

## EBP02-079: Destructive Impulse - Strategy Rank 4 (White)
## Perform the following action based on how many zones your monster card advanced
## through invasion this turn:
## 0 - <Destroy> all of your opponent's rank 2 or lower battle cards.
## 1 - <Destroy> all of your opponent's rank 4 or lower battle cards.
## 2 - <Destroy> all of your opponent's rank 6 or lower battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var zones_crossed: int = ctx.owner.invasion_zones_crossed
	var max_rank: int = 2  # 0 zones
	if zones_crossed >= 2:
		max_rank = 6
	elif zones_crossed >= 1:
		max_rank = 4

	var zones_to_destroy: Array[int] = []
	for i in range(8):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.opponent.player_id) <= max_rank:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
