extends CardEffect
# King Ghidorah(1998) (Battle R7)
# If there are 5 or more cards under your monster card, this card gains +3000 counter
# power.
#
# Tested: Yes
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
