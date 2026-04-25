extends CardEffect
## EBP04-045: Manda (2004) - Battle Rank 3 (Blue)
## When you play this from your hand, you may discard a non-blue battle card
## from your hand to decrease this card's rank by -2 (afterwards it's 3).
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	if not _hand_has_non_blue_battle(ctx.owner):
		return 0
	return -2


func apply_play_cost(ctx: EffectContext, zone_index: int) -> bool:
	if zone_index == -1:
		return true # Not a hand-to-zone play
	if not _hand_has_non_blue_battle(ctx.owner):
		return true # No discount claimed; normal play
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		_is_non_blue_battle,
		tr("STR_EFF_EBP04_045_PROMPT"),
		false)
	return not selected.is_empty()


func _is_non_blue_battle(card: Dictionary) -> bool:
	if not CardUtils.is_battle(card):
		return false
	return not CardUtils.has_color(card, CardEnums.CardColor.BLUE)


func _hand_has_non_blue_battle(player: PlayerState) -> bool:
	for card in player.hand:
		if not CardUtils.is_battle(card):
			continue
		if not CardUtils.has_color(card, CardEnums.CardColor.BLUE):
			return true
	return false
