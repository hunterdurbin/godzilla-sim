extends CardEffect
# Multi-purpose Fighting System-3 R2
# <When Invading> Reveal N cards from top of deck (N = opponent monster rank),
# add 1 red or blue battle card to hand, discard rest.


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
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

	# Find red or blue battle cards among revealed
	var valid: Array[Dictionary] = []
	for card in revealed:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			var card_colors: Array = card.get("colors", [])
			if CardEnums.CardColor.RED in card_colors or CardEnums.CardColor.BLUE in card_colors:
				valid.append(card)

	var chosen: Dictionary = await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, valid, revealed,
		"Choose 1 red or blue battle card to add to hand:")

	# Add chosen to hand, discard rest
	for card in revealed:
		if not chosen.is_empty() and card.get("id") == chosen.get("id"):
			ctx.owner.hand.append(card)
		else:
			ctx.owner.discard_pile.append(card)

	ctx.owner.hand_changed.emit()
	ctx.owner.discard_changed.emit()
