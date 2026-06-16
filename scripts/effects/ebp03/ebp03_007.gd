extends CardEffect
# Multi-purpose Fighting System-3 R2
# <When Invading> Reveal from the top of your deck a number of cards equal to the rank
# of your opponent’s monster card. Add 1 red or blue battle card among them to your
# hand, then send the rest to your discard pile.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "mill_self"]


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
		if CardUtils.is_battle(card):
			if CardUtils.has_color(card, CardEnums.CardColor.RED) or CardUtils.has_color(card, CardEnums.CardColor.BLUE):
				valid.append(card)

	var chosen: Dictionary = await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, valid, revealed,
		tr("STR_EFF_EBP03_007_SELECT"))

	# Add chosen to hand, discard rest
	for card in revealed:
		if not chosen.is_empty() and card.get("id") == chosen.get("id"):
			ctx.effect_handler.add_card_to_hand(ctx.owner.player_id, card)
		else:
			ctx.owner.discard_pile.append(card)

	ctx.owner.discard_changed.emit()
