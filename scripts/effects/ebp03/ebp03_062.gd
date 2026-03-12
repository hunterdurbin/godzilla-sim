extends CardEffect

## EBP03-062: Baragon(2001) - Battle Rank 6 (Green)
## When your opponent's monster card invades, Destroy this card.
## <Revenge> Return up to 1 Sacred Guardian Beast monster card from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func get_invasion_observed_filter() -> Dictionary:
	return {"own_turn": false}


func on_invasion_observed(ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	# Destroy self
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	var zones_to_destroy: Array[int] = [my_zone]
	await ctx.effect_handler.destroy_zones(ctx.owner, zones_to_destroy)


func on_revenge(ctx: EffectContext) -> void:
	# Return up to 1 Sacred Guardian Beast monster from discard to hand
	var selected: Dictionary = await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.MONSTER:
				return false
			return CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS in card.get("traits", []),
		"Return a Sacred Guardian Beast monster card from discard to hand:")

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
