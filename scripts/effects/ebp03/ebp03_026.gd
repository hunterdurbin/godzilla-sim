extends CardEffect

## EBP03-026: Mothra(imago)(2001) - Monster Rank 3 (Green)
## <Your Turn> If there are 3 or more cards under this card, reduce the rank of all
## battle cards in your opponent's zones by 2.
## <Enter> You may place 2 monster cards from your discard pile under this card.
## If you do, reduce your opponent's Rage by 1.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	if ctx.owner.monster_stack.size() < 3:
		return 0
	return -2


func on_enter(ctx: EffectContext) -> void:
	# Place up to 2 monster cards from discard under this card
	var placed: int = 0
	for _i in range(2):
		var selected: Dictionary = await ctx.effect_handler.search_discard(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool: return card.get("card_type") == CardEnums.CardType.MONSTER,
			"Place a monster card from discard under this card (%d of 2, or skip):" % (placed + 1))
		if selected.is_empty():
			break
		ctx.owner.monster_stack.append(selected)
		placed += 1

	if placed == 0:
		return

	ctx.owner.monster_changed.emit()

	# If placed at least 1, reduce opponent rage by 1
	if ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
