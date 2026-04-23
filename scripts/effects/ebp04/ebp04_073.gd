extends CardEffect
## EBP04-073: Gaira - Battle Rank 5 (White)
## <Opponent's Turn> Each time your opponent returns a card from their discard
## pile to their hand, if this is in area 1, return up to 1 card from your
## discard pile to your hand.
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


func on_card_returned_from_discard(ctx: EffectContext, _card: Dictionary) -> void:
	# Only active on opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return
	# This card must be in zone 1 (index 0)
	if find_zone_of_card(ctx) != 0:
		return

	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(c: Dictionary) -> bool: return true,
		"Gaira: Return 1 card from your discard to hand (or skip):")
	if not found.is_empty():
		ctx.owner.hand.append(found)
		ctx.owner.hand_changed.emit()
