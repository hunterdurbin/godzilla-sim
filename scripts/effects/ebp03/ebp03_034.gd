extends CardEffect
# Jet Jaguar(1973) (Battle R5)
# <Enter> Discard 1 strategy card from hand, reduce opponent rage by 1.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.rage > 0


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card to reduce opponent rage by 1 (or skip):",
		true
	)
	if selected.is_empty():
		return

	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
