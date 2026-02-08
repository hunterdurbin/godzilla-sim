extends CardEffect

## ESD02-009: Super-X - Battle Rank 4
## <Awakening4> <Enter> If this card is in zone 8, reduce your opponent's <Rage> by 1.
## (Active if your monster card is in zone 4 or beyond and this card was played in zone 8.)


func on_enter(ctx: EffectContext) -> void:
	# Awakening4: requires monster in zone 4+
	if ctx.owner.monster_zone < 4:
		return

	# Must be in zone 8 (index 7)
	if find_zone_of_card(ctx) != 7:
		return

	if ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
