extends CardEffect
# Multi-purpose Fighting System-3 R3
# <Enter> If there are 2 or more battle cards in your zones, your opponent discards
# cards until they have 4 cards remaining in their hand. If a battle card is discarded
# this way, increase this card’s <Rage> by 1.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "boosts_threat"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.get_battle_card_zone_indices().size() >= 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.get_battle_card_zone_indices().size() < 2:
		return

	var discarded := await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)

	# Gain 1 rage if a battle card was among the cards discarded this way.
	var battle_discarded := false
	for card in discarded:
		if CardUtils.is_battle(card):
			battle_discarded = true
			break

	if battle_discarded:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
