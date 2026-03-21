extends CardEffect

## EFC01-002: Gigan(Gojika Festival) - Battle Rank 5 (White)
## <Enter> If this card is in a zone adjacent to your monster card, send the top card
## of your deck to your discard pile. If it is a battle card, you may return up to 1
## monster card from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return
	var adjacent := get_adjacent_zones(monster_zone_idx)
	if zone_idx not in adjacent:
		return

	# Mill 1 card
	var milled: Array[Dictionary] = ctx.owner.mill_cards(1)
	if milled.is_empty():
		return
	ctx.effect_handler.log_message.emit(
		GameLog.effect_milled_cards(ctx.owner.player_id, ctx.card_data.get("id", ""), milled)
	)
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, milled, milled,
		"Sent to discard pile:")

	# If the milled card is a battle card, may return 1 monster from discard to hand
	if milled[0].get("card_type") != CardEnums.CardType.BATTLE:
		return

	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.MONSTER,
		"Return a monster card from discard to hand (or skip):")

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
