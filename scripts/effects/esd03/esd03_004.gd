extends CardEffect

## ESD03-004: Godzilla(2026) - Monster Rank 4 (Red)
## <Enter> Reveal cards from the top of your deck equal to the number of the
## zone this card is in. Add 1 red monster card with <《Godzilla》> from among
## them to your hand, then return the rest to your deck and shuffle it.
##
## Tested: Yes
## Known issues: None
## Edge cases: Deck smaller than the zone number → reveal what's there. No
##   red Godzilla monster revealed → the reveal is still shown, nothing is
##   added, and the deck is still shuffled.
## Rules: None
## Interactions: None
## Implementation notes: "Add 1" is mandatory — the pick can't be skipped
##   while a valid card is revealed.


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func on_enter(ctx: EffectContext) -> void:
	var count: int = ctx.owner.monster_zone
	if count <= 0 or ctx.owner.main_deck.is_empty():
		return

	var revealed: Array[Dictionary] = ctx.effect_handler.take_deck_top(ctx.owner.player_id, count)

	var valid: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_monster(card) \
				and CardUtils.has_color(card, CardEnums.CardColor.RED) \
				and CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA):
			valid.append(card)

	var chosen: Dictionary = await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, valid, revealed, tr("STR_EFF_ESD03_004_SELECT"), false)
	if not valid.is_empty() and chosen.is_empty():
		chosen = valid[0]  # Defensive: "Add 1" is mandatory.

	var rest: Array[Dictionary] = []
	for card in revealed:
		if not chosen.is_empty() and card.get("id") == chosen.get("id"):
			ctx.effect_handler.add_card_to_hand(ctx.owner.player_id, card)
		else:
			rest.append(card)
	ctx.effect_handler.shuffle_cards_into_deck(ctx.owner.player_id, rest)
