extends CardEffect
## EBP04-072: Sanda - Battle Rank 5 (White)
## <Opponent’s Turn> Whenever your opponent plays a battle card from their deck, if this
## card is in zone 5, you may search your deck for up to 1 card, add it to your hand,
## then shuffle your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_battle_card_played": {"own_turn": false, "played_by_opponent": true, "played_from_deck": true},
}


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_battle_card_played(ctx: EffectContext, _zone_index: int, _played_from_deck: bool = false) -> void:
	# Location check (zone 5 = index 4) stays inline — TRIGGER_FILTERS handles
	# turn ownership and the from-deck condition.
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 4:
		return
	var found := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(_card): return true,
		tr("STR_EFF_SEARCH_DECK_OR_SKIP"))
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
