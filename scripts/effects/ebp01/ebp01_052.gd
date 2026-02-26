extends CardEffect

## EBP01-052: Megaguirus - Battle Rank 5 (Blue)
## <Awakening4> If this card is in zones 1-5 and you have 5 or more monster cards
## in your discard pile, this card cannot be <Destroy> by your opponent's effects.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Uses can_be_destroyed system hook


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func can_be_destroyed(ctx: EffectContext) -> bool:
	# Awakening4: owner's monster must be in zone 4 or higher
	if ctx.owner.monster_zone < 4:
		return true
	# Must be in zones 1-5 (indices 0-4)
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0 or zone_idx > 4:
		return true
	# Need 5+ monster cards in discard
	if ctx.effect_handler.count_monsters_in_discard(ctx.owner) >= 5:
		return false
	return true
