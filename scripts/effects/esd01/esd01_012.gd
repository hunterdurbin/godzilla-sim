extends CardEffect

## ESD01-012: Godzilla(2023) - Battle Rank 7
## <Your Turn> When you play a monster card, you may move this card to an unoccupied zone.
## If this card is in zone 8, this card gains +3000 counter power.
## When this card is <Destroy>, place this card on the bottom of your deck instead.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent", "heals_deck"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]  # zone 8 (0-indexed) — gains +3000 CP in zone 8


func on_monster_played(ctx: EffectContext, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	# Only during your turn
	if ctx.is_opponent_turn():
		return

	# Find which zone this card is in
	var current_zone_idx: int = find_zone_of_card(ctx)
	if current_zone_idx < 0:
		return

	var empty_zones := ctx.owner.get_empty_zone_indices()
	if empty_zones.is_empty():
		return

	# Highlight this card to show its effect is being resolved
	ctx.effect_handler.highlight_zone_card(ctx.owner.player_id, current_zone_idx)

	# Let the player choose which empty zone to move to (may skip)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty_zones,
		tr("STR_EFF_ESD01_012_PROMPT"), true)

	ctx.effect_handler.unhighlight_zone_card(ctx.owner.player_id, current_zone_idx)

	if chosen < 0:
		return

	# Move the entire stack to the chosen zone
	var stack: Array = ctx.owner.clear_zone(current_zone_idx)
	ctx.owner.zones[chosen] = stack
	ctx.owner.zones_changed.emit()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# +3000 CP if in zone 8 (index 7)
	if find_zone_of_card(ctx) == 7:
		return 3000
	return 0


func on_revenge(ctx: EffectContext) -> void:
	ctx.effect_handler.return_to_deck_bottom(ctx.owner, ctx.card_data)


func on_crush(ctx: EffectContext) -> void:
	ctx.effect_handler.return_to_deck_bottom(ctx.owner, ctx.card_data)
