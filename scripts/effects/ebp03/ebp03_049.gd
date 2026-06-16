extends CardEffect
# Godzilla(2002) (Battle R6)
# <Enter> If this card is in zone 8, draw 2 cards, then discard 2 cards.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx != 7: # zone 8 = index 7
		return

	ctx.owner.draw_cards(2)

	# Discard 2 cards
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 2)
