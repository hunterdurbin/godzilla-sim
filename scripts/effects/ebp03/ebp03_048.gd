extends CardEffect
# Mechagodzilla(1993) (Battle R6)
# <Enter> If 2+ other battle cards in your zones, reduce opponent rage by 1.
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
	if opponent.rage <= 0:
		return false
	var battle_count: int = 0
	for i in range(8):
		if owner.zone_has_battle_card(i):
			battle_count += 1
			if battle_count >= 2:
				return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var my_id: String = ctx.card_data.get("id", "")
	var other_battle_count := 0
	for i in range(8):
		var card := ctx.owner.get_zone_top_card(i)
		if not card.is_empty() and card.get("id", "") != my_id:
			other_battle_count += 1

	if other_battle_count < 2:
		return

	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
