extends CardEffect
# Jet Jaguar(1973) (Battle R5)
# <Enter> You may discard 1 strategy card from your hand. If you do, reduce your
# opponent’s <Rage> by 1.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_rage()


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP03_034_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
