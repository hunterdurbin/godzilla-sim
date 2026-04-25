extends CardEffect
## EBP04-068: Kaiser Ghidorah - Battle Rank 8 (Red, Blue, Green)
## <Your Turn> If you have no strategy cards in play, decrease the ranks of
## strategy cards in your hand by -1 for each color of battle card in your
## discard pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, card: Dictionary, target_player_id: int) -> int:
	# Only affects own strategies, only on own turn
	if ctx.is_opponent(target_player_id):
		return 0
	if ctx.is_opponent_turn():
		return 0
	# Only applies to strategy cards in hand
	if not CardUtils.is_strategy(card):
		return 0
	# Only if no strategies currently in play
	if ctx.owner.has_any_strategy_in_play():
		return 0
	# Count distinct colors in discard
	var colors_seen: Array = []
	for discard_card in ctx.owner.discard_pile:
		for color in discard_card.get("colors", []):
			if color not in colors_seen:
				colors_seen.append(color)
	return -colors_seen.size()
