extends CardEffect

## EBP03-068: Godzilla Flies - Strategy Rank 3 (Red)
## <Your Turn> Your monster card cannot invade.
## Move your rank III or higher monster card in zone 3 vertically to zone 8. (Your
## battle cards in zones 4–7 will not be <Destroy> by this movement.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: 11.3 (crush) — zone 8 is crushed by the engine, not this script
## Interactions: None
## Implementation notes: teleport_monster (no crush on 4–7; destination crushed
## by the engine).


const TRIGGER_FILTERS = {
	"can_monster_invade": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["blocks_invade", "advances_self"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 8


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_zone == 3 and CardUtils.rank_at_least(owner.current_monster, 3)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false


func on_enter(ctx: EffectContext) -> void:
	# Move a rank III+ monster in zone 3 straight to zone 8. teleport_monster
	# skips zones 4–7; the engine crushes zone 8 itself (11.3), with Revenge,
	# replacement effects and leave-play handled by the single crush path.
	if ctx.owner.monster_zone != 3:
		return
	if not CardUtils.rank_at_least(ctx.owner.current_monster, 3):
		return
	await ctx.effect_handler.teleport_monster(ctx.owner.player_id, 8)
