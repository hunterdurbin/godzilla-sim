extends CardEffect
# Rainbow Mothra R3
# <Enter> Return 1 strategy card with <Base> from your discard pile to your hand.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.discard_pile:
		if CardUtils.is_strategy(card) and card.get("is_base", false):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return CardUtils.is_strategy(card) and card.get("is_base", false),
		"Return a Base strategy card from discard to hand:"
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
