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
	if not owner.is_awakening(4):
		return false
	return owner.has_zone_matching(func(c: Dictionary) -> bool:
		return c.get("name", "") == "Land Moguera")


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	# Only on your turn
	if ctx.is_opponent_turn():
		return
	# Awakening4: monster must be in zone 4+
	if not ctx.is_awakening(4):
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	# Find zones with "Land Moguera" as top card
	var land_moguera_zones: Array[int] = ctx.owner.get_zone_top_indices_matching(func(c: Dictionary) -> bool:
		return c.get("name", "") == "Land Moguera")
	land_moguera_zones.erase(my_zone)

	if land_moguera_zones.is_empty():
		return

	# Choose which Land Moguera to place under (optional)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, land_moguera_zones,
		tr("STR_EFF_EBP03_043_PROMPT"), true)

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
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.MOGUERA),
		tr("STR_EFF_EBP03_043_SEARCH"))

	if not selected.is_empty():
		await ctx.effect_handler.play_battle_card_from_deck(ctx.owner.player_id, selected, chosen)
