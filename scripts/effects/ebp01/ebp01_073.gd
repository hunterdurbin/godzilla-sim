extends CardEffect

## EBP01-073: Godzilla Against Mechagodzilla - Battle Rank 7 (White)
## This card cannot be played if you have 7 or fewer monster cards in your discard pile.
## When your monster card invades, if there are no monster cards under this card,
## you may place 1 monster card from your discard pile under this card to set your
## opponent's <Rage> to 0.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "weakens_opponent"]


func can_be_played(ctx: EffectContext) -> bool:
	# Cannot be played if 7 or fewer monster cards in discard pile (need 8+)
	return ctx.effect_handler.count_monsters_in_discard(ctx.owner) > 7


func get_invasion_observed_filter() -> Dictionary:
	return {"own_turn": true}


func on_invasion_observed(ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# Check if there are already monster cards under this card
	var stack: Array = ctx.owner.get_zone_stack(zone_idx)
	for i in range(1, stack.size()):
		if stack[i].get("card_type") == CardEnums.CardType.MONSTER:
			return # Already has a monster under it

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
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, ctx.opponent.rage)
