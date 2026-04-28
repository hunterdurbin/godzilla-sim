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
	if owner.count_strategies_in_play() > 1:
		return false
	if not owner.has_empty_strategy_zone():
		return false
	for card in owner.hand:
		if CardUtils.is_strategy(card) \
			and CardUtils.has_color(card, CardEnums.CardColor.BLUE) \
			and CardUtils.rank_at_most(card, 6):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.count_strategies_in_play() > 1:
		return

	if not ctx.owner.has_empty_strategy_zone():
		return

	# Find blue R6- strategy cards in hand
	var valid_indices: Array[int] = []
	for i in range(ctx.owner.hand.size()):
		var card: Dictionary = ctx.owner.hand[i]
		if CardUtils.is_strategy(card) \
			and CardUtils.has_color(card, CardEnums.CardColor.BLUE) \
			and CardUtils.rank_at_most(card, 6):
			valid_indices.append(i)

	if valid_indices.is_empty():
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_strategy(card) \
			and CardUtils.has_color(card, CardEnums.CardColor.BLUE) \
			and CardUtils.rank_at_most(card, 6),
		tr("STR_EFF_EBP03_012_PROMPT"),
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
