extends CardEffect
## EBP04-077: First Kiryu Commander Yashiro Akane - Strategy Rank 4 (Red)
## Reveal the top 3 cards of your deck, among those add 1 <Mechagodzilla> battle
## card and discard the rest. If the card you add to your hand is [MFS-3] or
## [Godzilla x MechaGodzilla] you may instead place it in Area 8.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 3)
	if revealed.is_empty():
		return

	# Find Mechagodzilla battle cards among revealed
	var mech_cards: Array[Dictionary] = []
	var non_mech_cards: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_battle(card) and CardUtils.has_trait(card, CardEnums.CardTrait.MECHAGODZILLA):
			mech_cards.append(card)
		else:
			non_mech_cards.append(card)

	ctx.effect_handler.discard_cards(ctx.owner.player_id, non_mech_cards)

	if mech_cards.is_empty():
		return

	# If multiple Mechagodzilla cards, pick one to add to hand
	var chosen_mech: Dictionary = mech_cards[0]
	if mech_cards.size() > 1:
		var mech_options := await ctx.effect_handler.select_from_cards(
			ctx.owner.player_id, mech_cards, mech_cards,
			tr("STR_EFF_EBP04_077_FROM_DECK"))
		if not mech_options.is_empty():
			chosen_mech = mech_options[0]

	# Discard the remaining Mechagodzilla cards
	var remaining_mech: Array[Dictionary] = []
	for card in mech_cards:
		if card.get("id", "") != chosen_mech.get("id", ""):
			remaining_mech.append(card)
	ctx.effect_handler.discard_cards(ctx.owner.player_id, remaining_mech)

	# Check if the chosen card is MFS-3 or Godzilla x MechaGodzilla
	var card_name: String = chosen_mech.get("name", "")
	var can_place_in_zone8: bool = (
		"MFS-3" in card_name or "Multipurpose Fighting System" in card_name or
		"Godzilla x MechaGodzilla" in card_name or
		chosen_mech.get("id", "") == "EBP04-043"
	)

	if can_place_in_zone8 and ctx.owner.zones[7].is_empty():
		var options: Array[String] = [
			tr("STR_EFF_EBP04_077_PLACE_8"),
			tr("STR_EFF_EBP04_077_PLACE_HAND"),
		]
		var place_chosen: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id, options,
			tr("STR_EFF_EBP04_077_PROMPT_FMT") % card_name)
		if place_chosen == 0:
			# Stage in discard so play_from_discard can remove+place+trigger enter cleanly.
			ctx.owner.discard_pile.append(chosen_mech)
			ctx.owner.discard_changed.emit()
			await ctx.effect_handler.play_from_discard(ctx.owner.player_id, chosen_mech, 7)
			return

	ctx.owner.hand.append(chosen_mech)
	ctx.owner.hand_changed.emit()
