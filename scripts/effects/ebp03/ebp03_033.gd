extends CardEffect
# Mechagodzilla(1975) (Battle R5)
# <Enter> Discard 1 R5+ battle card from hand, search deck for "Space Beam", add to hand.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5),
		tr("STR_EFF_EBP03_033_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card): return card.get("name", "") == "Space Beam",
		tr("STR_EFF_EBP03_033_SEARCH")
	)
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
