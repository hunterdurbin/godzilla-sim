extends CardEffect
# First Kiryu Commander Yashiro Akane
# Reveal top 3 of deck, add 1 Mechagodzilla battle card to hand, discard rest.
# If added card is MFS-3 or Godzilla x MechaGodzilla → may place in area 8 instead.


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var revealed: Array[Dictionary] = []
	for i in range(3):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())

	if revealed.is_empty():
		return

	ctx.effect_handler.cards_revealed_requested.emit(
		ctx.owner.player_id, revealed, "Revealed from deck top:")
	await ctx.effect_handler._cards_revealed_resolved

	# Find Mechagodzilla battle cards among revealed
	var mech_cards: Array[Dictionary] = []
	var non_mech_cards: Array[Dictionary] = []
	for card in revealed:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardTrait.MECHAGODZILLA in card.get("traits", [])):
			mech_cards.append(card)
		else:
			non_mech_cards.append(card)

	# Discard non-Mechagodzilla cards
	for card in non_mech_cards:
		ctx.owner.discard_pile.append(card)

	if mech_cards.is_empty():
		ctx.owner.deck_changed.emit()
		ctx.owner.discard_changed.emit()
		return

	# If multiple Mechagodzilla cards, pick one to add to hand
	var chosen_mech: Dictionary = mech_cards[0]
	if mech_cards.size() > 1:
		var mech_options := await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, mech_cards, mech_cards,
			"Choose 1 Mechagodzilla battle card to add to hand:")
		if not mech_options.is_empty():
			chosen_mech = mech_options[0]

	# Discard the remaining Mechagodzilla cards
	for card in mech_cards:
		if card.get("id", "") != chosen_mech.get("id", ""):
			ctx.owner.discard_pile.append(card)

	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	# Check if the chosen card is MFS-3 or Godzilla x MechaGodzilla
	var card_name: String = chosen_mech.get("name", "")
	var can_place_in_zone8: bool = (
		"MFS-3" in card_name or "Multipurpose Fighting System" in card_name or
		"Godzilla x MechaGodzilla" in card_name or
		chosen_mech.get("id", "") == "EBP04-043"
	)

	if can_place_in_zone8 and ctx.owner.zones[7].is_empty():
		var options: Array[String] = [
			"Place in Area 8",
			"Add to hand",
		]
		var place_chosen: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id, options,
			"%s — where would you like to place it?" % card_name)
		if place_chosen == 0:
			# Stage in discard so play_from_discard can remove+place+trigger enter cleanly.
			ctx.owner.discard_pile.append(chosen_mech)
			ctx.owner.discard_changed.emit()
			await ctx.effect_handler.play_from_discard(ctx.owner.player_id, chosen_mech, 7)
			return

	ctx.owner.hand.append(chosen_mech)
	ctx.owner.hand_changed.emit()
