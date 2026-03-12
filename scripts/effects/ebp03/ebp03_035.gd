extends CardEffect
# Satsuma (Battle R5)
# <Enter> If same column as opponent monster, discard 1 strategy from hand, advance own monster to zone 6.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_monster", "column_dependent_monster"]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx not in get_opponent_column_zones(zone_idx):
		return

	if ctx.owner.monster_zone >= 6:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card to advance your monster to zone 6 (or skip):",
		true
	)
	if selected.is_empty():
		return

	await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
