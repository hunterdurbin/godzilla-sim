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
	if invasion_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if CardEnums.CardColor.BLUE not in invasion_card.get("colors", []):
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

	# Optional — player may skip
	var valid_zones: Array[int] = []
	for i in range(8):
		if i != ctx.owner.monster_zone - 1:
			valid_zones.append(i)
	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		"Play %s from discard to a zone (or skip):" % invasion_card.get("name", "card"),
		true)
	if chosen < 0:
		return

	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, invasion_card, chosen)
