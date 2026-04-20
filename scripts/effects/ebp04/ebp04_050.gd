extends CardEffect
# Battra Larva
# When own monster invades and this is in area 8 → choose:
# 1) Draw 1 card and discard 1 card from hand.
# 2) Discard 1 card from hand to reduce opp rage by 1.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "draws_cards"]


func get_invasion_observed_filter() -> Dictionary:
	return {"own_turn": true}


func on_invasion_observed(ctx: EffectContext, invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	if invading_player_id != ctx.owner.player_id:
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7:  # Must be zone 8 (index 7)
		return

	var options: Array[String] = [
		"Draw 1 card, then discard 1 card from hand",
		"Discard 1 card from hand to reduce opponent's Rage by 1",
	]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options,
		"Choose one:")

	match chosen:
		0:
			ctx.owner.draw_cards(1)
			await ctx.effect_handler.select_hand_card(
				ctx.owner.player_id,
				func(_card): return true,
				"Discard 1 card from your hand:")
		1:
			var selected := await ctx.effect_handler.select_hand_card(
				ctx.owner.player_id,
				func(_card): return true,
				"Discard 1 card to reduce opponent's Rage by 1 (or skip):",
				true)
			if not selected.is_empty():
				await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
