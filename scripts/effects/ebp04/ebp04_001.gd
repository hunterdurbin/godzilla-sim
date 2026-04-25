extends CardEffect
## EBP04-001: Godzilla (2004) - Monster Rank 1 (Red)
## <Opponent's Turn> At the beginning of their counter phase, if there are no
## battle cards in the same column as this card, this card gains +1 <Rage>.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.COUNTER:
		return
	if ctx.is_own_turn():
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)

	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			return

	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1)
