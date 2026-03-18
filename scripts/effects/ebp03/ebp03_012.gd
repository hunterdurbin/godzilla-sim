extends CardEffect
# Godzilla(1993) R2
# <Enter> If you have 1 or fewer strategy cards in play, place up to 1 blue R6- strategy from hand.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "plays_other_cards"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var strategy_count := 0
	for sz in owner.strategy_zones:
		if not sz.is_empty():
			strategy_count += 1
	if strategy_count > 1:
		return false
	if not owner.has_empty_strategy_zone():
		return false
	for card in owner.hand:
		if card.get("card_type") == CardEnums.CardType.STRATEGY \
			and CardEnums.CardColor.BLUE in card.get("colors", []) \
			and card.get("rank", 0) <= 6:
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	# Count strategy cards in play
	var strategy_count := 0
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			strategy_count += 1

	if strategy_count > 1:
		return

	if not ctx.owner.has_empty_strategy_zone():
		return

	# Find blue R6- strategy cards in hand
	var valid_indices: Array[int] = []
	for i in range(ctx.owner.hand.size()):
		var card: Dictionary = ctx.owner.hand[i]
		if card.get("card_type") == CardEnums.CardType.STRATEGY \
			and CardEnums.CardColor.BLUE in card.get("colors", []) \
			and card.get("rank", 0) <= 6:
			valid_indices.append(i)

	if valid_indices.is_empty():
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.STRATEGY \
			and CardEnums.CardColor.BLUE in card.get("colors", []) \
			and card.get("rank", 0) <= 6,
		"Place a blue rank 6 or lower strategy card (or skip):",
		true
	)
	if selected.is_empty():
		return

	# select_hand_card already moved it to discard — move it from discard to strategy zone
	for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
		if ctx.owner.discard_pile[i].get("id") == selected.get("id"):
			var card: Dictionary = ctx.owner.discard_pile.pop_at(i)
			var sz_idx := ctx.owner.get_first_empty_strategy_zone_index()
			if sz_idx >= 0:
				ctx.owner.strategy_zones[sz_idx] = card
				ctx.owner.strategy_zones_changed.emit()
			ctx.owner.discard_changed.emit()
			# Trigger enter for the strategy card
			await ctx.effect_handler.trigger_enter(ctx.owner.player_id, card, true)
			break
