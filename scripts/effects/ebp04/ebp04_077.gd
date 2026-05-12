extends CardEffect
## EBP04-077: Akane Yashiro, The MFS-3 Unit - Strategy Rank 4 (Red)
## Reveal the top 3 cards of your deck. Add up to 1 《Mechagodzilla》 battle card from
## among them to your hand, and send the rest to your discard pile.
## If you added “Multi-purpose Fighting System-3” or “Godzilla Against Mechagodzilla”,
## you may play it in zone 8 instead.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var chosen_mech := await ctx.effect_handler.search_and_discard_deck_top(
		ctx.owner.player_id, 3,
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_trait(c, CardEnums.CardTrait.MECHAGODZILLA),
		tr("STR_EFF_EBP04_077_FROM_DECK"))
	if chosen_mech.is_empty():
		return

	var card_name: String = chosen_mech.get("name", "")
	var is_eligible_card: bool = (
		card_name == "Multi-purpose Fighting System-3"
		or card_name == "Godzilla Against Mechagodzilla"
	)
	# Honor the chosen card's own play restrictions: can_be_played (e.g. EBP01-073
	# needs 8+ monsters in discard) and any required-zone restriction. Playing
	# over an existing battle card in zone 8 is allowed — play_from_discard
	# handles overload by destroying the previous stack.
	var required_zones: Array[int] = ctx.effect_handler.get_card_required_play_zones(
		ctx.owner.player_id, chosen_mech)
	var zone8_allowed: bool = required_zones.is_empty() or 7 in required_zones
	var can_place_in_zone8: bool = (
		is_eligible_card
		and ctx.effect_handler.can_card_be_played(ctx.owner.player_id, chosen_mech)
		and zone8_allowed
	)

	if can_place_in_zone8:
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
