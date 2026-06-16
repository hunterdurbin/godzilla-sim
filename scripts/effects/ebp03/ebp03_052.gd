extends CardEffect

## EBP03-052: M.O.G.U.E.R.A. - Battle Rank 7 (Blue)
## When this card would be <Destroy> by an opponent’s effect, add all cards under this
## card to your hand.
## <Awakening6> <Enter> If there are no cards under this card, search your deck for up
## to 1 card named “Land Moguera” and up to 1 card named “Star Falcon”, place them under
## this card, then shuffle your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "draws_cards"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(6)


func on_would_be_destroyed(ctx: EffectContext) -> bool:
	# Add all cards under this card to hand before destruction
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return false

	var under_cards: Array = ctx.effect_handler.get_cards_under_top(ctx.owner, my_zone)
	if not under_cards.is_empty():
		for card in under_cards:
			ctx.owner.hand.append(card)
		# Clear zone stack to just the top card (self)
		var top_card: Dictionary = ctx.owner.get_zone_top_card(my_zone)
		ctx.owner.zones[my_zone] = [top_card]
		ctx.owner.hand_changed.emit()
		ctx.owner.zones_changed.emit()

	# Don't replace destruction — let it proceed normally
	return false


func on_enter(ctx: EffectContext) -> void:
	# Awakening6: monster must be in zone 6+
	if not ctx.is_awakening(6):
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	# Only if no cards under this card
	var under_cards: Array = ctx.effect_handler.get_cards_under_top(ctx.owner, my_zone)
	if not under_cards.is_empty():
		return

	# Search deck for Land Moguera
	var land_moguera: Dictionary = await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return card.get("name", "") == "Land Moguera",
		tr("STR_EFF_EBP03_052_LAND_SEARCH"))

	if not land_moguera.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, land_moguera, my_zone)

	# Search deck for Star Falcon
	var star_falcon: Dictionary = await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return card.get("name", "") == "Star Falcon",
		tr("STR_EFF_EBP03_052_STAR_SEARCH"))

	if not star_falcon.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, star_falcon, my_zone)
