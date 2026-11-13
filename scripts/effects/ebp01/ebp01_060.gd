extends CardEffect

## EBP01-060: Destoroyah Perfect Form - Battle Rank 8 (Blue)
## <Enter> If this card was played through evolution, choose up to 1 strategy card named
## 「Godzilla vs. Destoroyah」in your discard pile.
## If you have 1 or fewer strategy cards in play, play and activate the chosen card.
## (Regardless of rank.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func on_enter(ctx: EffectContext) -> void:
	if not ctx.card_data.get("played_through_evolution", false):
		return

	# Count active strategy cards (also guarantees an empty zone for the play)
	if ctx.owner.count_strategies_in_play() > 1 or not ctx.owner.has_empty_strategy_zone():
		return

	# Search discard for "Godzilla vs. Destoroyah" strategy
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_strategy(card) \
				and card.get("name", "") == "Godzilla vs. Destoroyah",
		tr("STR_EFF_EBP01_060_PROMPT")
	)
	if selected.is_empty():
		return

	# Play and activate it, regardless of rank (5.9.1)
	await ctx.effect_handler.play_strategy_from_effect(ctx.owner.player_id, selected)
