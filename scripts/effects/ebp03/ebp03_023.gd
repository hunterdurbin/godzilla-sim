extends CardEffect

## EBP03-023: Armor Mothra - Monster Rank 4 (Blue)
## <Enter> Evolve all of your Mothra battle cards with Evolution.
## When you successfully counter your opponent's monster card, if you have a card
## with <Base> in play, retreat your opponent's monster card back to zone 1.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["evolves", "retreats_opponent"]


func on_enter(ctx: EffectContext) -> void:
	# Collect eligible Mothra zones with Evolution
	var eligible: Array[int] = []
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("evolution_rank", -1) < 0:
			continue
		if CardEnums.CardTrait.MOTHRA not in zone_card.get("traits", []):
			continue
		eligible.append(i)

	# Let the player choose the order when multiple zones are eligible
	while not eligible.is_empty():
		var zi: int
		if eligible.size() == 1:
			zi = eligible.pop_back()
		else:
			var options: Array[String] = []
			for ez in eligible:
				var card := ctx.owner.get_zone_top_card(ez)
				options.append("Zone %d: %s" % [ez + 1, card.get("name", "?")])
			var chosen: int = await ctx.effect_handler.select_choice(
				ctx.owner.player_id, options, "Choose which zone to evolve next:")
			zi = eligible.pop_at(chosen)
		await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zi)


func on_counter_success(ctx: EffectContext) -> void:
	if not _has_base_in_play(ctx):
		return
	# Retreat opponent's monster to zone 1
	if ctx.opponent.monster_zone > 1:
		await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, 1)


func _has_base_in_play(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("is_base", false):
			return true
	return false
