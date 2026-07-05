extends CardEffect

## ESC01-002: Godzilla(1995) - Monster Rank 4 (Blue)
## <Enter> Play up to 1 rank 3 or lower battle card with <Evolution> from your
## discard pile, then evolve it.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Free zone choice (no adjacency clause on the card text,
## unlike EBP01-034). play_from_discard handles overload and fires the played
## card's <Enter> before the evolve step.


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "evolves"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.discard_pile:
		if CardUtils.is_battle(card) and card.get("rank", 0) <= 3 and card.has("evolution_rank"):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	# search_discard removes the selected card from the discard pile.
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_battle(card):
				return false
			if card.get("rank", 0) > 3:
				return false
			return card.has("evolution_rank"),
		tr("STR_EFF_ESC01_002_PROMPT")
	)
	if selected.is_empty():
		return

	var zone_idx: int = await ctx.effect_handler.play_from_discard(ctx.owner.player_id, selected)
	if zone_idx < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)
