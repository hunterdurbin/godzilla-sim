extends CardEffect

## EBP02-018: Despair - Strategy Rank 3 (Red)
## If your monster card has 2 or more <Rage>, <Destroy> 1 of your opponent's battle cards
## that is occupying a zone at or before the zone your monster card currently occupies.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage < 2:
		return

	var max_zone: int = ctx.owner.monster_zone  # 1-indexed
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool:
			# Find zone index of this card on opponent's board
			var card_id: String = card.get("id", "")
			for i in range(8):
				if ctx.opponent.get_zone_top_card(i).get("id", "") == card_id:
					return (i + 1) <= max_zone  # Zone number <= monster zone
			return false,
		"Choose an opponent's battle card at or before zone %d to destroy:" % max_zone)
