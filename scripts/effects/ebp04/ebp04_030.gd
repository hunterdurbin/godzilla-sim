extends CardEffect
## EBP04-030: Modified Gigan - Monster Rank 4 (Green)
## <Opponent's Turn> Your opponent cannot draw cards during their end phase.
## <Enter> <Destroy> 1 of your opponent's battle cards in zones 1-5.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func blocks_opponent_end_phase_draw(ctx: EffectContext) -> bool:
	return ctx.is_opponent_turn()


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_enter(ctx: EffectContext) -> void:
	var valid_zones: Array[int] = []
	for i in range(5):
		if ctx.opponent.zone_has_cards(i):
			valid_zones.append(i)
	if valid_zones.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
		tr("STR_EFF_DESTROY_OPP_BATTLE_ZONES_1_5"))
	if chosen >= 0:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
