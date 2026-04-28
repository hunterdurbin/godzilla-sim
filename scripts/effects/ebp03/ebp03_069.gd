extends CardEffect
# Space Beam (Strategy R4)
# Opponent discards to 4. If Mechagodzilla in your zone 8, Destroy all opponent R5-.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)

	# Check for Mechagodzilla in zone 8
	var zone8_card := ctx.owner.get_zone_top_card(7) # zone 8 = index 7
	if zone8_card.is_empty():
		return

	var has_mechagodzilla: bool = CardUtils.has_trait(zone8_card, CardEnums.CardTrait.MECHAGODZILLA)
	if not has_mechagodzilla:
		# Also check monster card if it's in zone 8
		if ctx.owner.monster_zone == 8:
			has_mechagodzilla = CardUtils.has_trait(ctx.owner.current_monster, CardEnums.CardTrait.MECHAGODZILLA)

	if not has_mechagodzilla:
		return

	var zones_to_destroy: Array[int] = ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 5)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
