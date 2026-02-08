extends CardEffect

## EBP01-052: Megaguirus - Battle Rank 5 (Blue)
## <Awakening4> If this card is in zones 1-5 and you have 5 or more monster cards
## in your discard pile, this card cannot be <Destroy> by your opponent's effects.
##
## NOTE: Destruction protection requires system-level support in destroy_zone_target
## and destroy_zones. This effect declares the protection conditions.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func _is_protected(ctx: EffectContext) -> bool:
	if ctx.owner.monster_zone < 4:
		return false
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0 or zone_idx > 4:
		return false
	return _count_monsters_in_discard(ctx.owner) >= 5


func _count_monsters_in_discard(player: PlayerState) -> int:
	var count: int = 0
	for card in player.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			count += 1
	return count
