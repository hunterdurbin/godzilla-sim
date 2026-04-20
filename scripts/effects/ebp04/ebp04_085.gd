extends CardEffect
# The Golden Demise
# <Base>
# When moved from strategy zones to discard + 2+ green battle in own zones → return to hand.
# <Opponent's Turn> Higher Dimensional Monster Ghidorah in own zones 1-5 cannot be Destroyed.


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func is_base_strategy() -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_strategy_discarded(ctx: EffectContext, strategy_card: Dictionary) -> void:
	if strategy_card.get("id", "") != ctx.card_data.get("id", ""):
		return

	var green_count: int = 0
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if (not zone_card.is_empty() and
				zone_card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in zone_card.get("colors", [])):
			green_count += 1

	if green_count < 2:
		return

	# Remove from discard and add to hand
	var idx: int = ctx.owner.discard_pile.rfind(strategy_card)
	if idx < 0:
		for i in range(ctx.owner.discard_pile.size()):
			if ctx.owner.discard_pile[i].get("id", "") == strategy_card.get("id", ""):
				idx = i
				break
	if idx >= 0:
		ctx.owner.discard_pile.remove_at(idx)
		ctx.owner.hand.append(strategy_card)
		ctx.owner.discard_changed.emit()
		ctx.owner.hand_changed.emit()


func protects_card_from_destruction(ctx: EffectContext, card_data: Dictionary, zone_idx: int) -> bool:
	# Opponent's Turn: protect Higher Dimensional Monster Ghidorah in zones 1-5
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return false
	if zone_idx >= 5:
		return false
	return CardEnums.CardTrait.HIGHER_DIMENSIONAL in card_data.get("traits", [])
