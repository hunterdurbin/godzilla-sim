extends CardEffect
# Godzilla(1993) R2
# <Enter> If you have 1 or fewer strategy cards in play, you may place up to 1 blue
# rank 6 or lower strategy card from your hand into your strategy zone and activate it.
#
# Tested: Yes
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

	var selected := await ctx.effect_handler.take_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_strategy(card) \
			and CardUtils.has_color(card, CardEnums.CardColor.BLUE) \
			and CardUtils.rank_at_most(card, 6),
		tr("STR_EFF_EBP03_012_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	# Place it into the strategy zone and activate it (5.9.1: activate = play).
	# take_hand_card removes it from hand without discarding it.
	await ctx.effect_handler.play_strategy_from_effect(ctx.owner.player_id, selected)
