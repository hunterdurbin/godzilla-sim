extends CardEffect
# Mechagodzilla(1993) (Battle R6)
# <Enter> If there are 2 or more other battle cards in your zones, reduce your
# opponent’s <Rage> by 1.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	if not opponent.has_rage():
		return false
	return owner.get_battle_card_zone_indices().size() >= 2


func on_enter(ctx: EffectContext) -> void:
	var my_id: String = ctx.card_data.get("id", "")
	var other_battle_count: int = ctx.owner.count_zones_matching(func(c: Dictionary) -> bool:
		return c.get("id", "") != my_id)

	if other_battle_count < 2:
		return

	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
