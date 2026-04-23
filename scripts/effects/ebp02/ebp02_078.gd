extends CardEffect

## EBP02-078: Mothra(imago)(2003) - Battle Rank 7 (White)
## <Enter> If this card is in the same column as your opponent's monster card,
## reveal the top 2 cards of your deck. Add all rank 5 or lower battle cards among
## them to your hand and send the rest into your discard pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["column_dependent_monster", "draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var opp_columns := get_opponent_column_zones(zone_idx)
	if opp_monster_idx not in opp_columns:
		return

	# Reveal top 2
	var revealed: Array[Dictionary] = []
	for _i in range(2):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())
	ctx.owner.deck_changed.emit()

	if revealed.is_empty():
		return

	# Show revealed cards to the player
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		"Revealed from deck (select any to confirm):")

	var added_to_hand: bool = false
	var added_to_discard: bool = false

	for card in revealed:
		if CardUtils.is_battle(card) and card.get("rank", 0) <= 5:
			ctx.owner.hand.append(card)
			added_to_hand = true
		else:
			ctx.owner.discard_pile.append(card)
			added_to_discard = true

	if added_to_hand:
		ctx.owner.hand_changed.emit()
	if added_to_discard:
		ctx.owner.discard_changed.emit()
