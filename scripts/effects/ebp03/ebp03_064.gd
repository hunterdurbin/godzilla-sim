extends CardEffect

## EBP03-064: Mothra(imago)(2001) - Battle Rank 7 (Green)
## <Enter> If an opponent's battle card was Destroyed this turn, you may place 1 battle
## card from your discard pile under this card.
## <Awakening4> If there is a card under this card, this card gains +3000 counter power.
## <Awakening6> If there is a card under this card, this card gains an additional +3000 CP.


func on_enter(ctx: EffectContext) -> void:
	# Check if opponent had a card destroyed this turn
	if ctx.opponent.cards_destroyed_this_turn.is_empty():
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	# Place 1 battle card from discard under this card (optional)
	var selected: Dictionary = await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return card.get("card_type") == CardEnums.CardType.BATTLE,
		"Place a battle card from discard under this card:")

	if not selected.is_empty():
		ctx.effect_handler.place_card_under_zone(ctx.owner, selected, my_zone)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return 0

	var under_cards: Array = ctx.effect_handler.get_cards_under_top(ctx.owner, my_zone)
	if under_cards.is_empty():
		return 0

	var bonus: int = 0
	# Awakening4: monster in zone 4+
	if ctx.owner.monster_zone >= 4:
		bonus += 3000
	# Awakening6: monster in zone 6+
	if ctx.owner.monster_zone >= 6:
		bonus += 3000
	return bonus
