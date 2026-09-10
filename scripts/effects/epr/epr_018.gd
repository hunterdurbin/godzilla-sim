extends CardEffect

## EPR-018: GODZILLA THE RIDE: GREAT CLASH - Strategy Rank 5 (Blue)
## Discard 1 card from your hand. If you do, search your deck for up to 1
## <《Mech》>, <《Weapon》>, or <《GODZILLA THE RIDE》> battle card, reveal it, add it
## to your hand, then shuffle your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: The discard is the cost — with an empty hand nothing
## is discarded and the search does not happen ("If you do").


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return not owner.hand.is_empty()


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.hand.is_empty():
		return

	var discarded: Dictionary = await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		tr("STR_EFF_EPR_018_DISCARD"))
	if discarded.is_empty():
		return

	var found: Dictionary = await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_any_trait(card, [
				CardEnums.CardTrait.MECH,
				CardEnums.CardTrait.WEAPON,
				CardEnums.CardTrait.GODZILLA_THE_RIDE,
			]),
		tr("STR_EFF_EPR_018_SEARCH"))
	if not found.is_empty():
		ctx.effect_handler.add_card_to_hand(ctx.owner.player_id, found)
