extends CardEffect

## EBP01-045: Meganula - Battle Rank 2 (Blue)
## <Enter> If this card is in the same column as your opponent's monster card and you
## have 2 or more battle cards in your zones, reduce your opponent's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) not in opp_columns:
		return

	var battle_count: int = 0
	for i in range(8):
		if ctx.owner.zone_has_cards(i):
			battle_count += 1
	if battle_count < 2:
		return

	if ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
