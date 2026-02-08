extends CardEffect

## EBP01-020: Anguirus(1968) - Battle Rank 3
## If this card is in zone 8, whenever your monster card invades, you may reduce its
## <Rage> by 1 to search your deck for up to 1 monster card with <Burst>, reveal it,
## add it to your hand, then shuffle your deck.


func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if _find_zone_of_card(ctx) != 7:
		return
	# Only during invasion (main phase)
	if ctx.game_state.current_phase != CardEnums.GamePhase.MAIN:
		return
	if ctx.owner.rage <= 0:
		return

	# Cost: reduce rage by 1
	ctx.owner.rage -= 1
	ctx.owner.rage_changed.emit(ctx.owner.rage)

	var selected := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.MONSTER:
				return false
			var effect := ctx.effect_handler.get_effect(card)
			return effect != null and effect.get_burst_rank() >= 0,
		"Search for a monster card with Burst to add to your hand:"
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
