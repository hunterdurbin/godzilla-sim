extends CardEffect

## EBP03-042: Ghogo - Battle Rank 2 (Blue)
## When your monster card invades, if this is in zone 8, you may put this card under one
## of your Mothra battle cards with Evolution. If you do, evolve that Mothra battle card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_invasion_observed": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["evolves", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]


func on_invasion_observed(ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	# Must be in zone 8 (index 7)
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7:
		return

	# Find Mothra battle cards with Evolution in owner's zones
	var valid_zones: Array[int] = ctx.owner.get_zone_top_indices_matching(func(c: Dictionary) -> bool:
		return c.get("evolution_rank", -1) >= 0 and CardUtils.has_trait(c, CardEnums.CardTrait.MOTHRA))
	valid_zones.erase(my_zone)

	if valid_zones.is_empty():
		return

	# Choose a Mothra card to place self under (optional)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_EBP03_042_PROMPT"), true)

	if chosen < 0:
		return

	# Remove self from zone 8 and place under the chosen card
	var self_stack: Array = ctx.owner.clear_zone(my_zone)
	if not self_stack.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, self_stack[0], chosen)
		# Banish/discard any cards that were stacked under self
		if self_stack.size() > 1:
			EffectHandler.banish_or_discard(ctx.owner, self_stack.slice(1))
	ctx.owner.zones_changed.emit()

	# Evolve the chosen card
	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, chosen)
