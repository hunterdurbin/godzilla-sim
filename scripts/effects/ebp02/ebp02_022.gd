extends CardEffect

## EBP02-022: Godzilla(1994) - Monster Rank 4 (Blue)
## <When Invading> If you discarded a blue battle card for this card's invade action,
## you may play that battle card from your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var invasion_card: Dictionary = ctx.owner.last_invasion_card
	if invasion_card.is_empty():
		return
	# Must be a blue battle card
	if not CardUtils.is_battle(invasion_card):
		return
	if not CardUtils.has_color(invasion_card, CardEnums.CardColor.BLUE):
		return

	# Check the card is still in discard
	var card_id: String = invasion_card.get("id", "")
	var found := false
	for card in ctx.owner.discard_pile:
		if card.get("id", "") == card_id:
			found = true
			break
	if not found:
		return

	await ctx.effect_handler.play_from_discard_or_skip(
		ctx.owner.player_id, invasion_card,
		tr("STR_EFF_PLACE_DISCARD_FMT") % invasion_card.get("name", "card"))
