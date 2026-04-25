extends CardEffect
## EBP04-072: Sanda - Battle Rank 5 (White)
## <Opponent's Turn> Each time your opponent plays a card from their deck, if
## this is in area 5, search your deck for up to 1 card, add it to your hand,
## and shuffle your deck.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_battle_card_played(ctx: EffectContext, _zone_index: int, played_from_deck: bool = false) -> void:
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	if not played_from_deck:
		return
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 4:  # Zone 5 = index 4
		return
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(_card): return true,
		tr("STR_EFF_SEARCH_DECK_OR_SKIP"))
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
