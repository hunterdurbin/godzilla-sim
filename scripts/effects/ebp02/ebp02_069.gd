extends CardEffect

## EBP02-069: Godzilla vs. SpaceGodzilla - Strategy Rank 1 (Green)
## Choose 2 of your opponent's battle cards in their zones and swap their positions.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var occupied: Array[int] = []
	for i in range(8):
		if ctx.opponent.zone_has_cards(i):
			occupied.append(i)

	if occupied.size() < 2:
		return

	var first: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, occupied,
		"Choose the first opponent battle card to swap:")
	if first < 0:
		return

	var second_choices: Array[int] = []
	for zi in occupied:
		if zi != first:
			second_choices.append(zi)

	var second: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, second_choices,
		"Choose the second opponent battle card to swap with:")
	if second < 0:
		return

	await ctx.effect_handler.swap_zones(ctx.opponent, first, second)
