extends CardEffect
## EBP04-088: Kidnapped Monsters - Strategy Rank 8 (Green)
## Return up to 2 non-green battle cards from your discard pile to your hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["recycles_from_discard"]


func on_enter(ctx: EffectContext) -> void:
	var matching: Array[Dictionary] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and not CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			matching.append(card)
	if matching.is_empty():
		return

	# 'Up to 2' — min_count=0 lets the player confirm any amount including zero.
	var selected := await ctx.effect_handler.select_cards_from_pool(
		ctx.owner.player_id, matching, ctx.owner.discard_pile.duplicate(),
		tr("STR_EFF_EBP04_088_PROMPT"), 0, 2)
	for card in selected:
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, card)
