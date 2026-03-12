extends CardEffect
# Aqua Mothra R4
# If you have a card with <Base> in play, +10000 threat level.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if _has_base_in_play(ctx):
		return 10000
	return 0


func _has_base_in_play(ctx: EffectContext) -> bool:
	for strategy in ctx.owner.strategy_zones:
		if not strategy.is_empty() and strategy.get("is_base", false):
			return true
	return false
