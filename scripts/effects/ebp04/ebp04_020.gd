extends CardEffect
## EBP04-020: Aqua Mothra - Monster Rank 4 (Blue, Green)
## <Enter> If you have a Base in play, <Destroy> all battle cards adjacent to
## your opponent's monster card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for sz in owner.strategy_zones:
		if not sz.is_empty() and sz.get("is_base", false):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	if not _has_base(ctx):
		return

	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var adjacent := get_adjacent_zones(opp_monster_idx)

	var zones_to_destroy: Array[int] = []
	for zi in adjacent:
		if ctx.opponent.zone_has_cards(zi):
			zones_to_destroy.append(zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)


func _has_base(ctx: EffectContext) -> bool:
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty() and sz.get("is_base", false):
			return true
	return false
