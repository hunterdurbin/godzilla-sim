extends CardEffect
## EBP04-039: Zilla - Battle Rank 4 (Red)
## <Opponent's Turn> Each time one of your non-red battle cards are <Destroy>,
## move this card to an area adjacent to your monster card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_ally_zone_card_destroyed(ctx: EffectContext, destroyed_card: Dictionary, _zone_idx: int) -> void:
	# Only active on opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return

	# Destroyed card must be a non-red battle card (not this card itself)
	if destroyed_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if CardEnums.CardColor.RED in destroyed_card.get("colors", []):
		return

	# Find where this card currently is
	var self_zone := find_zone_of_card(ctx)
	if self_zone < 0:
		return

	# Find zones adjacent to own monster
	var monster_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_idx)
	var valid_targets: Array[int] = []
	for zi in adjacent:
		if zi != self_zone:
			valid_targets.append(zi)

	if valid_targets.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_targets,
		"Zilla: Move to a zone adjacent to your monster (or skip):", true)
	if chosen < 0:
		return

	# Move this card
	ctx.owner.zones[self_zone].erase(ctx.card_data)
	ctx.owner.zones[chosen].push_front(ctx.card_data)
	ctx.owner.zones_changed.emit()
