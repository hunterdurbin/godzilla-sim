extends CardEffect

## EBP01-059: Fire Rodan - Battle Rank 7 (Blue)
## When this card is discarded from your hand by your opponent's effect, and their
## monster card is in zones 4-8, you may play this card.
## If this card is in zone 8, this card gains +3000 counter power.
##
## NOTE: The discard-from-hand play trigger requires system support to interrupt
## the discard and play the card instead. The CP modifier is fully implemented.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if find_zone_of_card(ctx) == 7:
		return 3000
	return 0


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Check if opponent's monster is in zones 4-8
	if ctx.opponent.monster_zone < 4:
		return

	# Play this card from discard to an empty zone
	var empty_zones := ctx.owner.get_empty_zone_indices()
	if empty_zones.is_empty():
		return

	# Find and remove this card from discard pile
	var card_id: String = ctx.card_data.get("id", "")
	var card_index: int = -1
	for i in range(ctx.owner.discard_pile.size()):
		if ctx.owner.discard_pile[i].get("id", "") == card_id:
			card_index = i
			break
	if card_index < 0:
		return

	var target_zone: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty_zones,
		"Choose a zone to play Fire Rodan:", true)
	if target_zone < 0:
		return

	var card: Dictionary = ctx.owner.discard_pile.pop_at(card_index)
	ctx.owner.push_zone_card(target_zone, card)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, card)
