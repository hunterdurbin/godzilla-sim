extends CardEffect

## EBP03-004: Godzilla(2001) - Monster Rank 4 (Red)
## When this card invades, you may send the top card of your deck to your discard pile
## instead of discarding a card from your hand.
## <Opponent's Turn> <Awakening4> This card's Rage cannot be reduced by your opponent's
## effects. (Active if this is in zone 4 or beyond.)
##
## NOTE: The invasion replacement (mill vs hand discard) requires ActionHandler changes
## to offer a choice before the normal discard. Currently implemented as a partial:
## - The rage reduction prevention is fully implemented via on_rage_changed interception.
## - The invasion replacement is a TODO requiring deeper invasion flow changes.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.REPLACEMENT]


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# <Opponent's Turn> <Awakening4>: Rage cannot be reduced by opponent's effects
	# If it's opponent's turn and Awakening4, and rage was reduced, restore it
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return  # Only active on opponent's turn
	if ctx.owner.monster_zone < 4:
		return  # Awakening4 not active
	if new_rage < old_rage:
		# Restore rage to old value (prevent reduction)
		ctx.owner.rage = old_rage
		ctx.owner.rage_changed.emit(ctx.owner.rage)
