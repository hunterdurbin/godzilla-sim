extends CardEffect

## EBP02-079: Destructive Impulse - Strategy Rank 4 (White)
## Perform the following action based on how many zones your monster card advanced
## through invasion this turn:
## 0 - <Destroy> all of your opponent's rank 2 or lower battle cards.
## 1 - <Destroy> all of your opponent's rank 4 or lower battle cards.
## 2 - <Destroy> all of your opponent's rank 6 or lower battle cards.
## NOTE: Exact invasion zone tracking needs game_state.invasion_zones_crossed.
## For now, uses has_invaded_this_turn as a basic check (0 vs 1+).


func on_enter(ctx: EffectContext) -> void:
	# Determine max rank to destroy based on invasion distance
	# TODO: Track exact invasion zone count in GameState for full 0/1/2 distinction.
	# Currently has_invaded_this_turn is boolean, so we can only distinguish 0 vs 1+.
	var max_rank: int = 2  # Default: 0 zones invaded
	if ctx.owner.has_invaded_this_turn:
		max_rank = 4  # At least 1 zone

	var zones_to_destroy: Array[int] = []
	for i in range(8):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("rank", 0) <= max_rank:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
