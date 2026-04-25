extends CardEffect

## ESD02-014: The Legend of Infant Island - Strategy Rank 5
## Evolve 1 of your battle cards with <Evolution>.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["evolves"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for i in range(8):
		var zone_card := owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.has("evolution_rank"):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var player := ctx.owner

	# Find all zones with battle cards that have Evolution
	var valid_zones: Array[int] = []
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.has("evolution_rank"):
			valid_zones.append(i)

	if valid_zones.is_empty():
		return

	# Let player choose which card to evolve
	var chosen: int = await ctx.effect_handler.select_zone_target(
		player.player_id, player.player_id, valid_zones,
		tr("STR_EFF_EVOLVE_BATTLE"))
	if chosen < 0:
		return

	await ctx.effect_handler.perform_evolution(player.player_id, chosen)
