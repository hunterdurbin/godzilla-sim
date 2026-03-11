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

	# Collect all red or blue battle cards from revealed
	var valid: Array[Dictionary] = []
	for card in revealed:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			var colors: Array = card.get("colors", [])
			if CardEnums.CardColor.RED in colors or CardEnums.CardColor.BLUE in colors:
				valid.append(card)

	# Pool filter: at most 1 red, at most 1 blue (dual-color cards count as both)
	var filter := func(card: Dictionary, selection: Array[Dictionary]) -> bool:
		var card_colors: Array = card.get("colors", [])
		var has_red: bool = CardEnums.CardColor.RED in card_colors
		var has_blue: bool = CardEnums.CardColor.BLUE in card_colors
		# Count how many red/blue already selected
		var red_count: int = 0
		var blue_count: int = 0
		for sel in selection:
			var sel_colors: Array = sel.get("colors", [])
			if CardEnums.CardColor.RED in sel_colors:
				red_count += 1
			if CardEnums.CardColor.BLUE in sel_colors:
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
		"Choose up to 1 red and 1 blue battle card to add to hand:", 0, 2, filter)

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
