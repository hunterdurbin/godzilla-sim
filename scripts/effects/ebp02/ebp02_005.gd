extends CardEffect

## EBP02-005: Godzilla(2016) 3rd Form - Monster Rank 3 (Red)
## <Your Turn> <Awakening6> Whenever this card's <Rage> is increased, if you have a
## strategy card in play, your opponent discards cards until they have 3 cards remaining.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand"]


func bot_can_fulfill_on_rage_changed(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_zone >= 6


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	if new_rage <= old_rage:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return
	if ctx.owner.monster_zone < 6:
		return

	var has_strategy: bool = ctx.owner.has_any_strategy_in_play()

	if has_strategy:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)
