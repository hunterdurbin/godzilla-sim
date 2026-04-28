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

	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 2)
	if revealed.is_empty():
		return

	var to_hand: Array[Dictionary] = []
	var to_discard: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_battle(card) and CardUtils.rank_at_most(card, 5):
			to_hand.append(card)
		else:
			to_discard.append(card)

	if not to_hand.is_empty():
		ctx.owner.hand.append_array(to_hand)
		ctx.owner.hand_changed.emit()
	ctx.effect_handler.discard_cards(ctx.owner.player_id, to_discard)
