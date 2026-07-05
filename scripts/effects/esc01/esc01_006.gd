extends CardEffect

## ESC01-006: Mothra(imago)(1992) - Battle Rank 7 (White)
## <Enter> You may discard your entire hand; for each strategy card discarded by
## this effect, increase your monster card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.hand:
		if CardUtils.is_strategy(card):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.hand.is_empty():
		return

	var options: Array[String] = [
		tr("STR_EFF_ESC01_006_CHOICE_A"),
		tr("STR_EFF_ESC01_006_CHOICE_B"),
	]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, tr("STR_EFF_CHOOSE_EFFECT"))
	if chosen != 0:
		return

	var discarded: Array[Dictionary] = await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, 0)
	var strategy_count: int = 0
	for card in discarded:
		if CardUtils.is_strategy(card):
			strategy_count += 1
	if strategy_count > 0:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, strategy_count, ctx.card_data.get("id", ""))
