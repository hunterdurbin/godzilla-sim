extends CardEffect

## EBP02-044: Modified Gigan - Monster Rank 4 (Green)
## <When Invading> If your opponent's monster card is in zones 6-8, reduce their <Rage> by 2.
## At the beginning of your end phase, if your opponent's monster card is in zones 1-5,
## increase this card's <Rage> by 2.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "weakens_opponent"]



func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.opponent.monster_zone >= 6:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 2)


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	if ctx.opponent.monster_zone <= 5:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 2)
