extends CardEffect

## EBP01-006: Godzilla(1974) - Monster Rank 3
## <Opponent's Turn> At the beginning of the counter phase, <Destroy> all of your
## opponent's rank 5 or lower battle cards in the same column as this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_battle"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	# Opponent's turn only
	if ctx.is_own_turn():
		return

	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var column_zones := get_opponent_column_zones(monster_zone_idx)

	var zones_to_destroy: Array[int] = []
	for zi in column_zones:
		var zone_card := ctx.opponent.get_zone_top_card(zi)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.opponent.player_id) <= 5:
			zones_to_destroy.append(zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
