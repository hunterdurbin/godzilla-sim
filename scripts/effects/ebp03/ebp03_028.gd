extends CardEffect

## EBP03-028: Thousand-Year Dragon King Ghidorah - Monster Rank 4 (Green)
## <Your Turn> If there are 5 or more cards under this card, reduce the rank of all
## battle cards in your opponent's zones by 3.
## <Opponent's Turn> At the beginning of the counter phase, you may place 3 monster cards
## from your discard pile under this card. If you do, Destroy all rank 5 or lower battle
## cards in your opponent's zones 1-5.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	if ctx.owner.monster_stack.size() < 5:
		return 0
	return -3


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	# Only on opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return

	# Place up to 3 monster cards from discard under this card
	var placed: int = 0
	for _i in range(3):
		var selected: Dictionary = await ctx.effect_handler.search_discard(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool: return card.get("card_type") == CardEnums.CardType.MONSTER,
			"Place a monster card from discard under this card (%d of 3, or skip):" % (placed + 1))
		if selected.is_empty():
			break
		ctx.owner.monster_stack.append(selected)
		placed += 1

	if placed == 0:
		return

	ctx.owner.monster_changed.emit()

	# Destroy all R5 or lower battle cards in opponent's zones 1-5 (indices 0-4)
	var zones_to_destroy: Array[int] = []
	for i in range(5):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.opponent.player_id) <= 5:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
