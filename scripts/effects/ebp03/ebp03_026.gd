extends CardEffect

## EBP03-026: Mothra(imago)(2001) - Monster Rank 3 (Green)
## <Your Turn> If there are 3 or more cards under this card, reduce the rank of all
## battle cards in your opponent's zones by 2.
## <Enter> You may place 2 monster cards from your discard pile under this card.
## If you do, reduce your opponent's Rage by 1.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_count := 0
	for card in owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
			if monster_count >= 2:
				return true
	return false


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	if ctx.owner.monster_stack.size() < 3:
		return 0
	return -2


func on_enter(ctx: EffectContext) -> void:
	# Place exactly 2 monster cards from discard under this card (or skip entirely)
	var monsters: Array[Dictionary] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card):
			monsters.append(card)

	if monsters.size() < 2:
		return

	var selected: Array[Dictionary] = await ctx.effect_handler.select_cards_from_pool(
		ctx.owner.player_id, monsters, ctx.owner.discard_pile.duplicate(),
		tr("STR_EFF_EBP03_026_SELECT"), 2)

	if selected.is_empty():
		return

	# Remove selected cards from discard pile
	for card in selected:
		var card_id: String = card.get("id", "")
		for i in range(ctx.owner.discard_pile.size()):
			if ctx.owner.discard_pile[i].get("id") == card_id:
				ctx.owner.discard_pile.remove_at(i)
				break

	# Place under monster
	for card in selected:
		ctx.owner.monster_stack.append(card)

	ctx.owner.discard_changed.emit()
	ctx.owner.monster_changed.emit()

	# Reduce opponent rage by 1
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
