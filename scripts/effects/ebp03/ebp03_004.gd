extends CardEffect
# Godzilla(2001) - Monster Rank 4 (Red)
# When this card invades, you may send the top card of your deck to your discard pile
# instead of discarding a card from your hand.
# <Opponent's Turn> <Awakening4> This card's Rage cannot be reduced by your opponent's
# effects. (Active if this is in zone 4 or beyond.)


func can_replace_invasion_cost(_ctx: EffectContext) -> bool:
	return true


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# <Opponent's Turn> <Awakening4>: Rage cannot be reduced by opponent's effects
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return  # Only active on opponent's turn
	if ctx.owner.monster_zone < 4:
		return  # Awakening4 not active
	if new_rage < old_rage:
		# Restore rage to old value (prevent reduction)
		ctx.owner.rage = old_rage
		ctx.owner.rage_changed.emit(ctx.owner.rage)
