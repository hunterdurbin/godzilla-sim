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


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)

	# Check for Mechagodzilla in zone 8
	var zone8_card := ctx.owner.get_zone_top_card(7)  # zone 8 = index 7
	if zone8_card.is_empty():
		return

	var has_mechagodzilla: bool = CardEnums.CardTrait.MECHAGODZILLA in zone8_card.get("traits", [])
	if not has_mechagodzilla:
		# Also check monster card if it's in zone 8
		if ctx.owner.monster_zone == 8:
			has_mechagodzilla = CardEnums.CardTrait.MECHAGODZILLA in ctx.owner.current_monster.get("traits", [])

	if not has_mechagodzilla:
		return

	var zones_to_destroy: Array[int] = []
	for i in range(8):
		var opp_card := ctx.opponent.get_zone_top_card(i)
		if not opp_card.is_empty() and opp_card.get("rank", 0) <= 5:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
