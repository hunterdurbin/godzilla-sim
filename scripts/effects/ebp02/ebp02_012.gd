extends CardEffect

## EBP02-012: Godzilla(2016) Frozen - Battle Rank 4 (Red)
## If this card is in zone 8, whenever your strategy cards would be discarded from
## the strategy zone, you may place them under this card instead.
## <Awakening4> At the beginning of your main phase, if there are 2 or more cards
## under this card, counter your opponent's monster card.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.REPLACEMENT]


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	# Only on your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	# Must be in zone 8
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx != 7:
		return
	# Awakening4: monster must be in zone 4+
	if ctx.owner.monster_zone < 4:
		return
	# Need 2+ cards under this card (stack size > 1 since the card itself is the top)
	var stack_size: int = ctx.owner.get_zone_stack(zone_idx).size()
	if stack_size < 3:  # 1 (self) + 2 (under)
		return
	# TODO: Trigger a forced counter on opponent's monster card.
	# Requires calling into ActionHandler.resolve_counter() or adding a
	# counter_requested signal on EffectHandler for the ActionHandler to connect to.
	pass


# TODO: Implement replacement effect for strategy card discard interception.
# When strategy cards would be discarded from the strategy zone during start phase,
# if this card is in zone 8, the player may place them under this card instead.
# Needs a hook in ActionHandler.execute_start_phase() to check for this card.
