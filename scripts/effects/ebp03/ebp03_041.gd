extends CardEffect

## EBP03-041: Godzilla(2023) - Battle Rank 8 (Red)
## <Enter> If this is in the same column as your opponent's monster card and your monster
## card has 2 or more Rage, reduce your opponent's Rage by 2.
## When this card would be Destroyed, put this card on the bottom of your deck instead.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	# Check if same column as opponent's monster
	var opp_monster_zone_idx: int = ctx.opponent.monster_zone - 1
	var my_column_zones: Array[int] = get_opponent_column_zones(my_zone)
	if opp_monster_zone_idx not in my_column_zones:
		return

	# Check own rage >= 2
	if ctx.owner.rage < 2:
		return

	# Reduce opponent rage by 2
	if ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage = maxi(0, ctx.opponent.rage - 2)
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)


func on_would_be_destroyed(_ctx: EffectContext) -> bool:
	# Move to deck bottom instead of being destroyed
	return true
