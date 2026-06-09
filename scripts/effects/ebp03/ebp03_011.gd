extends CardEffect
# Multi-purpose Fighting System-3 R4
# <Burst3> (You can play this card from rank III. If you do, send this card to your
# discard pile at the beginning of your next end phase.)
# <Enter> Reveal from the top of your deck a number of cards equal to the rank of your
# opponent’s monster card. Add up to 1 red battle card and up to 1 blue battle card
# among them to your hand, then send the rest to your discard pile.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "mill_self"]


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

	# Collect all red or blue battle cards from revealed
	var valid: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_battle(card):
			if CardUtils.has_color(card, CardEnums.CardColor.RED) or CardUtils.has_color(card, CardEnums.CardColor.BLUE):
				valid.append(card)

	# Pool filter: at most 1 red, at most 1 blue (dual-color cards count as both)
	var filter := func(card: Dictionary, selection: Array[Dictionary]) -> bool:
		var has_red: bool = CardUtils.has_color(card, CardEnums.CardColor.RED)
		var has_blue: bool = CardUtils.has_color(card, CardEnums.CardColor.BLUE)
		# Count how many red/blue already selected
		var red_count: int = 0
		var blue_count: int = 0
		for sel in selection:
			if CardUtils.has_color(sel, CardEnums.CardColor.RED):
				red_count += 1
			if CardUtils.has_color(sel, CardEnums.CardColor.BLUE):
				blue_count += 1
		# Card is selectable if it can contribute a color not yet at limit
		if has_red and red_count >= 1 and has_blue and blue_count >= 1:
			return false
		if has_red and not has_blue and red_count >= 1:
			return false
		if has_blue and not has_red and blue_count >= 1:
			return false
		return true

	var chosen: Array[Dictionary] = await ctx.effect_handler.select_cards_from_pool(
		ctx.owner.player_id, valid, revealed,
		tr("STR_EFF_EBP03_011_SELECT"), 0, 2, filter)

	var chosen_ids: Array[String] = []
	for card in chosen:
		chosen_ids.append(card.get("id", ""))

	# Add chosen to hand, discard rest
	var to_hand: Array[Dictionary] = []
	for card in revealed:
		if card.get("id", "") in chosen_ids:
			to_hand.append(card)
		else:
			ctx.owner.discard_pile.append(card)

	ctx.effect_handler.add_cards_to_hand(ctx.owner.player_id, to_hand)
	ctx.owner.discard_changed.emit()
