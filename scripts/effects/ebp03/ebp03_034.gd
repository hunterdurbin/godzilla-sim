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


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card to reduce opponent rage by 1 (or skip):",
		true
	)
	if selected.is_empty():
		return

	if ctx.opponent.rage > 0:
		var old_rage := ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
