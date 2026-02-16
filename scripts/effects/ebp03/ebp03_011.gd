extends CardEffect
# Multi-purpose Fighting System-3 R4
# <Burst3>
# <Enter> Reveal N cards (N = opponent monster rank), add up to 1 red + 1 blue battle card, discard rest.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


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

	var chosen: Array[Dictionary] = []

	# Collect all red or blue battle cards from revealed
	var red_or_blue: Array[Dictionary] = []
	for card in revealed:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			var colors: Array = card.get("colors", [])
			if CardEnums.CardColor.RED in colors or CardEnums.CardColor.BLUE in colors:
				red_or_blue.append(card)

	# First pick: choose 1 red or blue battle card (always show revealed cards)
	var first := await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, red_or_blue, revealed,
		"Choose up to 1 red or blue battle card to add to hand (or skip):")
	if not first.is_empty():
		chosen.append(first)
		var first_colors: Array = first.get("colors", [])
		# Second pick: the other color (or either if first was dual-color)
		var second_options: Array[Dictionary] = []
		var second_prompt: String
		if CardEnums.CardColor.RED in first_colors and CardEnums.CardColor.BLUE not in first_colors:
			for card in red_or_blue:
				if card.get("id", "") != first.get("id", "") and CardEnums.CardColor.BLUE in card.get("colors", []):
					second_options.append(card)
			second_prompt = "Choose up to 1 blue battle card to add to hand (or skip):"
		elif CardEnums.CardColor.BLUE in first_colors and CardEnums.CardColor.RED not in first_colors:
			for card in red_or_blue:
				if card.get("id", "") != first.get("id", "") and CardEnums.CardColor.RED in card.get("colors", []):
					second_options.append(card)
			second_prompt = "Choose up to 1 red battle card to add to hand (or skip):"
		else:
			# Dual-color: either color is still valid
			for card in red_or_blue:
				if card.get("id", "") != first.get("id", ""):
					second_options.append(card)
			second_prompt = "Choose up to 1 red or blue battle card to add to hand (or skip):"
		if not second_options.is_empty():
			var second := await ctx.effect_handler.select_from_cards(
				ctx.owner.player_id, second_options, revealed, second_prompt)
			if not second.is_empty():
				chosen.append(second)

	var chosen_ids: Array[String] = []
	for card in chosen:
		chosen_ids.append(card.get("id", ""))

	# Add chosen to hand, discard rest
	for card in revealed:
		if card.get("id", "") in chosen_ids:
			ctx.owner.hand.append(card)
		else:
			ctx.owner.discard_pile.append(card)

	ctx.owner.hand_changed.emit()
	ctx.owner.discard_changed.emit()
