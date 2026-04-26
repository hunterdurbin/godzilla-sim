extends CardEffect
# Multi-purpose Fighting System-3 R3
# <Enter> If 2+ battle cards in your zones, opponent discards to 4.
# If a battle card was discarded this way, +1 rage.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "boosts_threat"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.get_occupied_zone_indices().size() >= 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.get_occupied_zone_indices().size() < 2:
		return

	# Track opponent hand before discard
	var hand_before: Array[Dictionary] = []
	for card in ctx.opponent.hand:
		hand_before.append(card)

	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)

	# Check if any battle card was discarded
	var battle_discarded := false
	for card in hand_before:
		if card not in ctx.opponent.hand:
			if CardUtils.is_battle(card):
				battle_discarded = true
				break

	if battle_discarded:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
