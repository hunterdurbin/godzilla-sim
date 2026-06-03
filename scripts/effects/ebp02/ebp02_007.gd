extends CardEffect

## EBP02-007: Godzilla(2016) 4th Form - Monster Rank 4 (Red)
## <Burst3> (You can play this card from rank III. If you do, send this card to your
## discard pile at the beginning of your next end phase.)
## <Enter> You may discard 1 strategy card from your hand. If you do, reveal the top 5
## cards of your deck, add 1 monster card from among them to your hand, then send the
## rest to your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "mill_self"]


func get_burst_rank() -> int:
	return 3


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP02_007_PROMPT"),
		true)

	if selected.is_empty():
		return

	# Reveal top 5
	var revealed: Array[Dictionary] = []
	for _i in range(5):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())
	ctx.owner.deck_changed.emit()

	var monsters: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_monster(card):
			monsters.append(card)
		else:
			rest.append(card)

	var chosen: Dictionary = await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, monsters, revealed,
		tr("STR_EFF_EBP02_007_SELECT"))

	if not chosen.is_empty():
		var card_id: String = chosen.get("id", "")
		for i in range(monsters.size()):
			if monsters[i].get("id", "") == card_id:
				ctx.effect_handler.add_card_to_hand(ctx.owner.player_id, monsters[i])
				monsters.remove_at(i)
				break

	rest.append_array(monsters)
	ctx.owner.discard_pile.append_array(rest)
	if not rest.is_empty():
		ctx.owner.discard_changed.emit()
