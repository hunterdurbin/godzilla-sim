extends CardEffect

## EBP02-046: King Ghidorah(1965) - Monster Rank 3 (Green)
## <Enter> Place all cards with the same name as this card from your discard pile under
## this card.
## This card gains +3000 threat level for each card with the same name under this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var my_name: String = ctx.card_data.get("name", "")
	var to_stack: Array[Dictionary] = []

	# Find matching cards in discard pile (iterate backwards for safe removal)
	for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
		if ctx.owner.discard_pile[i].get("name", "") == my_name:
			to_stack.append(ctx.owner.discard_pile.pop_at(i))

	if not to_stack.is_empty():
		# Add to monster_stack (cards under the monster)
		ctx.owner.monster_stack.append_array(to_stack)
		ctx.owner.discard_changed.emit()
		ctx.owner.monster_changed.emit()


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var my_name: String = ctx.card_data.get("name", "")
	var count: int = 0
	for card in ctx.owner.monster_stack:
		if card.get("name", "") == my_name:
			count += 1
	return count * 3000
