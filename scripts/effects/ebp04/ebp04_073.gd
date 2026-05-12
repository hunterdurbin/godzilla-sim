extends CardEffect
## EBP04-073: Gaira - Battle Rank 5 (White)
## <Opponent’s Turn> Whenever your opponent returns a card from their discard pile to
## their hand, if this card is in zone 1, you may return up to 1 card from your discard
## pile to your hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_card_returned_from_discard": {"own_turn": false, "returned_by_opponent": true},
}


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_card_returned_from_discard(ctx: EffectContext, _card: Dictionary) -> void:
	# This card must be in zone 1 (index 0) — location check stays inline.
	if find_zone_of_card(ctx) != 0:
		return

	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(_c: Dictionary) -> bool: return true,
		tr("STR_EFF_EBP04_073_PROMPT"))
	if not found.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
