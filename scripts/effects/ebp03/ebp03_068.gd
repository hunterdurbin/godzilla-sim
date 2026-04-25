extends CardEffect

## EBP03-068: Godzilla Flies - Strategy Rank 3 (Red)
## <Your Turn> Your monster card cannot invade.
## Move your rank III or higher monster card in zone 3 vertically to zone 8.
## (Your battle cards in zones 4-7 will not be Destroyed by this movement.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["blocks_invade", "advances_self"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 8


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_zone == 3 and owner.CardUtils.rank_at_least(current_monster, 3)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func prevents_own_invasion(ctx: EffectContext) -> bool:
	# Only on your turn
	if ctx.is_opponent_turn():
		return false
	return true


func on_enter(ctx: EffectContext) -> void:
	# Move monster from zone 3 to zone 8 if rank 3+
	if ctx.owner.monster_zone != 3:
		return
	if ctx.owner.current_monster.get("rank", 0) < 3:
		return

	# Move directly to zone 8 (no crush on zones 4-7)
	var old_zone: int = ctx.owner.monster_zone
	ctx.owner.monster_zone = 8
	ctx.owner.monster_changed.emit()
	# Only trigger crush on zone 8 (skip 4-7)
	# Check if zone 8 (index 7) has a battle card to crush
	if ctx.owner.zone_has_cards(7):
		var crushed_stack: Array = ctx.owner.clear_zone(7)
		EffectHandler.banish_or_discard(ctx.owner, crushed_stack)
		ctx.owner.zones_changed.emit()
		ctx.owner.discard_changed.emit()
		await ctx.effect_handler.trigger_crush(ctx.owner.player_id, crushed_stack[0])
