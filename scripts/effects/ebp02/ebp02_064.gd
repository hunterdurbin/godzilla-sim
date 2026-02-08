extends CardEffect

## EBP02-064: Gigan(1972) - Battle Rank 6 (Green)
## If there is a card with <King Ghidorah> or <Megalon> in your zones,
## this card gains +3000 counter power.
## <Revenge> Return up to 1 <King Ghidorah> monster card from your discard pile
## to your hand.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if top.is_empty():
			continue
		var traits: Array = top.get("traits", [])
		if CardEnums.CardTrait.KING_GHIDORAH in traits or CardEnums.CardTrait.MEGALON in traits:
			return 3000
	return 0


func on_revenge(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if card.get("card_type") != CardEnums.CardType.MONSTER:
				return false
			var traits: Array = card.get("traits", [])
			return CardEnums.CardTrait.KING_GHIDORAH in traits,
		"Return a King Ghidorah monster card to your hand:")

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
