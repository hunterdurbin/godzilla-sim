extends CardEffect
# Manda (2004)
# When played from hand, may discard a non-blue battle card from hand to
# decrease this card's rank by -2 for the play (afterwards it's the original rank).
# Simplification: the -2 play rank modifier applies whenever a non-blue battle card
# is available in hand; apply_play_cost then requires the discard.


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	if not _hand_has_non_blue_battle(ctx.owner):
		return 0
	return -2


func apply_play_cost(ctx: EffectContext, zone_index: int) -> bool:
	if zone_index == -1:
		return true # Not a hand-to-zone play
	if not _hand_has_non_blue_battle(ctx.owner):
		return true # No discount claimed; normal play
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		_is_non_blue_battle,
		"Discard a non-blue battle card (play cost for Manda -2 rank):",
		false)
	return not selected.is_empty()


func _is_non_blue_battle(card: Dictionary) -> bool:
	if card.get("card_type") != CardEnums.CardType.BATTLE:
		return false
	return CardEnums.CardColor.BLUE not in card.get("colors", [])


func _hand_has_non_blue_battle(player: PlayerState) -> bool:
	for card in player.hand:
		if card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if CardEnums.CardColor.BLUE not in card.get("colors", []):
			return true
	return false
