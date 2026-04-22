extends CardEffect

## EBP03-043: Star Falcon - Battle Rank 3 (Blue)
## <Awakening4> At the beginning of your counter phase, you may place this card under a
## card named "Land Moguera" in your zones. If you do, search your deck for up to 1
## Moguera battle card, play it on top of the "Land Moguera" you chose, then shuffle.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "plays_other_cards"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	if owner.monster_zone < 4:
		return false
	for i in range(8):
		var zone_card := owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("name", "") == "Land Moguera":
			return true
	return false


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	# Only on your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	# Awakening4: monster must be in zone 4+
	if ctx.owner.monster_zone < 4:
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	# Find zones with "Land Moguera" as top card
	var land_moguera_zones: Array[int] = []
	for i in range(8):
		if i == my_zone:
			continue
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("name", "") == "Land Moguera":
			land_moguera_zones.append(i)

	if land_moguera_zones.is_empty():
		return

	# Choose which Land Moguera to place under (optional)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, land_moguera_zones,
		"Place Star Falcon under Land Moguera (or skip):", true)

	if chosen < 0:
		return

	# Remove self from current zone and place under the chosen Land Moguera
	var self_stack: Array = ctx.owner.clear_zone(my_zone)
	if not self_stack.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, self_stack[0], chosen)
		if self_stack.size() > 1:
			EffectHandler.banish_or_discard(ctx.owner, self_stack.slice(1))
	ctx.owner.zones_changed.emit()

	# Search deck for a Moguera battle card and play it on top of Land Moguera
	var selected: Dictionary = await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.BATTLE:
				return false
			return CardEnums.CardTrait.MOGUERA in card.get("traits", []),
		"Search for a Moguera battle card to play on Land Moguera:")

	if not selected.is_empty():
		ctx.owner.push_zone_card(chosen, selected)
		ctx.owner.zones_changed.emit()
		await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected, true)
		await ctx.effect_handler.trigger_battle_card_played(ctx.owner.player_id, selected, chosen, true)
