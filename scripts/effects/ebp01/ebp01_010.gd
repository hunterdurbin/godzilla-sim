extends CardEffect

## EBP01-010: Godzilla(2023) - Monster Rank 4
## Whenever this card's <Rage> is increased, <Destroy> all of your opponent's battle cards
## in the same column as this card.
## <Opponent's Turn> At the beginning of the counter phase, if this card has 3 or more <Rage>,
## <Destroy> all of your opponent's battle cards in the same column as this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_battle"]


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	if new_rage <= old_rage:
		return
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var column_zones := get_opponent_column_zones(monster_zone_idx)
	await ctx.effect_handler.destroy_zones(ctx.opponent, column_zones)


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.is_own_turn():
		return
	if ctx.owner.rage < 3:
		return
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var column_zones := get_opponent_column_zones(monster_zone_idx)
	await ctx.effect_handler.destroy_zones(ctx.opponent, column_zones)
