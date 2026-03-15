extends CardEffect

## EBP03-025: Mothra(imago)(2001) - Monster Rank 2 (Green)
## <Your Turn> Reduce the rank of all battle cards in your opponent's zones by 1.
## <Enter> You may place 1 monster card from your discard pile under this card.
## If you do, advance your opponent's monster card to zone 5.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "advances_opponent"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	# Only active during your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	return -1


func on_enter(ctx: EffectContext) -> void:
	# Place 1 monster card from discard under this card (optional)
	var selected: Dictionary = await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return card.get("card_type") == CardEnums.CardType.MONSTER,
		"Place a monster card from discard under this card (or skip):")

	if selected.is_empty():
		return

	ctx.owner.monster_stack.append(selected)
	ctx.owner.monster_changed.emit()

	# Advance opponent's monster to zone 5 (if not already at 5+)
	if ctx.opponent.monster_zone < 5:
		await ctx.effect_handler.advance_monster_to_zone(ctx.opponent.player_id, 5)
