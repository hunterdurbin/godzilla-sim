extends CardEffect
# King Ghidorah(1998) (Battle R7)
# If 5+ cards under your monster card, +3000 CP.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_monster_stack(5)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.has_monster_stack(5):
		return 3000
	return 0
