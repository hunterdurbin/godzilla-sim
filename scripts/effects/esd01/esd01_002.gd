extends CardEffect

## ESD01-002: Godzilla(2023) - Monster Rank 2
## <When Invading> Search your deck for up to 1 rank III card named Godzilla(2023)
## with <Burst>, reveal it, add it to your hand, then shuffle your deck.
## (If you invaded 2 zones, activate this effect 2 times)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["searches_deck"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await _search_for_burst_godzilla(ctx)


func _search_for_burst_godzilla(ctx: EffectContext) -> void:
	var player := ctx.owner
	var selected := await ctx.effect_handler.search_deck(
		player.player_id,
		func(card: Dictionary) -> bool:
			if card.get("name", "") != "Godzilla(2023)": return false
			if card.get("rank", 0) != 3: return false
			if card.get("card_type") != CardEnums.CardType.MONSTER: return false
			var effect := ctx.effect_handler.get_effect(card)
			return effect != null and effect.get_burst_rank() >= 0,
		"Search for a Rank III Godzilla(2023) with Burst"
	)
	if not selected.is_empty():
		player.hand.append(selected)
		player.hand_changed.emit()
