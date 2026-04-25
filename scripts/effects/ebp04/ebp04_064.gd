extends CardEffect
## EBP04-064: Jet Jaguar (2021) - Battle Rank 6 (Green)
## At the beginning of your counter phase, if you have 10 or more green battle
## cards in your discard pile, you may <Destroy> this to reduce your opponent's
## <Rage> by 3.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.is_opponent_turn():
		return
	if ctx.opponent.rage < 3:
		return

	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			green_count += 1
	if green_count < 10:
		return

	var selected := await ctx.effect_handler.select_choice(
		ctx.owner.player_id,
		[tr("STR_EFF_EBP04_064_CHOICE"), tr("STR_EFF_BTN_SKIP")],
		tr("STR_EFF_EBP04_064_PROMPT"))
	if selected != 0:
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 3)
