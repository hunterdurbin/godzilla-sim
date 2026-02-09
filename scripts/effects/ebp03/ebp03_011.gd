extends CardEffect
# Multi-purpose Fighting System-3 R4
# <Burst3>
# <Enter> Reveal N cards (N = opponent monster rank), add up to 1 red + 1 blue battle card, discard rest.


func get_burst_rank() -> int:
	return 3


func on_enter(ctx: EffectContext) -> void:
	var n: int = ctx.opponent.get_monster_rank()
	if n <= 0:
		return

	var revealed: Array[Dictionary] = []
	for _i in range(n):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())
	ctx.owner.deck_changed.emit()

	if revealed.is_empty():
		return

	var chosen_ids: Array[String] = []

	# Pick up to 1 red battle card
	var red_options: Array[Dictionary] = []
	for card in revealed:
		if card.get("card_type") == CardEnums.CardType.BATTLE and card.get("color") == CardEnums.CardColor.RED:
			red_options.append(card)
	if not red_options.is_empty():
		var red_chosen := await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, red_options, revealed,
			"Choose up to 1 red battle card to add to hand (or skip):")
		if not red_chosen.is_empty():
			chosen_ids.append(red_chosen.get("id", ""))

	# Pick up to 1 blue battle card
	var blue_options: Array[Dictionary] = []
	for card in revealed:
		if card.get("card_type") == CardEnums.CardType.BATTLE and card.get("color") == CardEnums.CardColor.BLUE:
			if card.get("id", "") not in chosen_ids:
				blue_options.append(card)
	if not blue_options.is_empty():
		var blue_chosen := await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, blue_options, revealed,
			"Choose up to 1 blue battle card to add to hand (or skip):")
		if not blue_chosen.is_empty():
			chosen_ids.append(blue_chosen.get("id", ""))

	# Add chosen to hand, discard rest
	for card in revealed:
		if card.get("id", "") in chosen_ids:
			ctx.owner.hand.append(card)
		else:
			ctx.owner.discard_pile.append(card)

	ctx.owner.hand_changed.emit()
	ctx.owner.discard_changed.emit()
