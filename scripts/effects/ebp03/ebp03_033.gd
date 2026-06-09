extends CardEffect
# Mechagodzilla(1975) (Battle R5)
# <Enter> You may discard 1 rank 5 or higher battle card from your hand. If you do,
# search your deck for up to 1 card named “Space Beam”, reveal it, add it to your hand,
# then shuffle your deck.
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
		ctx.effect_handler.add_card_to_hand(ctx.owner.player_id, found)
