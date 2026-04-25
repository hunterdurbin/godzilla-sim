extends CardEffect

## EBP03-029: Thousand-Year Dragon King Ghidorah - Monster Rank 4 (Green)
## <Your Turn> If there are 5 or more cards under this card, reduce the rank of all
## battle cards in your opponent's zones by 3.
## <When Invading> If there are 7 or more cards under this card, choose one:
## - Destroy all battle cards of both players.
## - Each player discards cards until they have 2 cards remaining in their hand.
## - Reduce each player's monster card's Rage by 2.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "destroys_zone", "disrupts_hand"]


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_monster_stack(7)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	if ctx.is_opponent_turn():
		return 0
	if not ctx.has_monster_stack(5):
		return 0
	return -3


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if not ctx.has_monster_stack(7):
		return

	var options: Array[String] = [
		tr("STR_EFF_EBP03_029_CHOICE_A"),
		tr("STR_EFF_EBP03_029_CHOICE_B"),
		tr("STR_EFF_EBP03_029_CHOICE_C")
	]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, tr("STR_EFF_CHOOSE_ONE"))

	match chosen:
		0:
			# Destroy all battle cards of both players
			for pid in range(2):
				var player := ctx.game_state.players[pid]
				var zones_to_destroy: Array[int] = player.get_occupied_zone_indices()
				if not zones_to_destroy.is_empty():
					await ctx.effect_handler.destroy_zones(player, zones_to_destroy)
		1:
			# Each player discards to 2
			for pid in range(2):
				if ctx.game_state.players[pid].hand.size() > 2:
					await ctx.effect_handler.discard_hand_to(pid, 2)
		2:
			# Reduce each player's rage by 2
			for pid in range(2):
				await ctx.effect_handler.reduce_rage(pid, 2)
