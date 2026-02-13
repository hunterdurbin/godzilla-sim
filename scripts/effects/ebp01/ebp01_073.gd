extends CardEffect

## EBP01-073: Godzilla Against Mechagodzilla - Battle Rank 7 (White)
## This card cannot be played if you have 7 or fewer monster cards in your discard pile.
## When your monster card invades, if there are no monster cards under this card,
## you may place 1 monster card from your discard pile under this card to set your
## opponent's <Rage> to 0.
##
## NOTE: The play restriction requires rules engine support.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Only during invasion (main phase)
	if ctx.game_state.current_phase != CardEnums.GamePhase.MAIN:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# Check if there are already monster cards under this card
	var stack: Array = ctx.owner.get_zone_stack(zone_idx)
	for i in range(1, stack.size()):
		if stack[i].get("card_type") == CardEnums.CardType.MONSTER:
			return  # Already has a monster under it

	# Search discard for a monster card to place under
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.MONSTER,
		"Place a monster card from your discard pile under this card to set opponent's Rage to 0:"
	)
	if selected.is_empty():
		return

	# Place under this card
	ctx.owner.zones[zone_idx].append(selected)
	ctx.owner.zones_changed.emit()

	# Set opponent's rage to 0
	ctx.opponent.rage = 0
	ctx.opponent.rage_changed.emit(0)
