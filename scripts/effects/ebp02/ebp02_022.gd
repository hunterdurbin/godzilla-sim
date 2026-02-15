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


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var invasion_card: Dictionary = ctx.owner.last_invasion_card
	if invasion_card.is_empty():
		return
	# Must be a blue battle card
	if invasion_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if CardEnums.CardColor.BLUE not in invasion_card.get("colors", []):
		return

	# Find the card in discard pile
	var card_id: String = invasion_card.get("id", "")
	var discard_idx: int = -1
	for i in range(ctx.owner.discard_pile.size()):
		if ctx.owner.discard_pile[i].get("id", "") == card_id:
			discard_idx = i
			break
	if discard_idx < 0:
		return

	# Let player choose a zone to place it
	var valid_zones: Array[int] = []
	for i in range(8):
		if (ctx.owner.monster_zone - 1) != i:
			valid_zones.append(i)
	if valid_zones.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		"Play %s from discard to a zone (or skip):" % invasion_card.get("name", "card"),
		true)

	if chosen < 0:
		return

	# Remove from discard and place in zone
	var card: Dictionary = ctx.owner.discard_pile.pop_at(discard_idx)
	ctx.owner.discard_changed.emit()

	# Handle overload (existing card in zone)
	if ctx.owner.zone_has_cards(chosen):
		var destroyed_stack: Array = ctx.owner.clear_zone(chosen)
		ctx.owner.discard_pile.append_array(destroyed_stack)
		ctx.owner.discard_changed.emit()
		await ctx.effect_handler.trigger_revenge(ctx.owner.player_id, destroyed_stack[0])

	ctx.owner.push_zone_card(chosen, card)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, card)
