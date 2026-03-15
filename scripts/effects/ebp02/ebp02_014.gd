extends CardEffect

## EBP02-014: Cabinet Helicopter - Battle Rank 6 (Red)
## <Enter> Send the top card of your deck to your discard pile.
## If it is a monster card, advance your monster card to zone 6.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "advances_self"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()
	ctx.effect_handler.log_message.emit(
		GameLog.effect_milled_card(ctx.owner.player_id, ctx.card_data.get("id", ""), card.get("id", ""))
	)

	var revealed: Array[Dictionary] = [card]
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		"Sent to discard pile:")

	if card.get("card_type") == CardEnums.CardType.MONSTER:
		if ctx.owner.monster_zone < 6:
			await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
