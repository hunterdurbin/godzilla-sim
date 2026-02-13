extends CardEffect

## EBP02-060: Gigan(2004) - Battle Rank 4 (Green)
## If this card is in the same column as your opponent's monster card,
## this card gains +3000 counter power.
## <Revenge> If your opponent's monster card is in zones 1-5, you may return this card
## from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var opp_columns := get_opponent_column_zones(zone_idx)
	if opp_monster_idx in opp_columns:
		return 3000
	return 0


func on_revenge(ctx: EffectContext) -> void:
	if ctx.opponent.monster_zone > 5:
		return
	# Return this card from discard to hand
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
		if ctx.owner.discard_pile[i].get("id", "") == card_id:
			var card: Dictionary = ctx.owner.discard_pile.pop_at(i)
			ctx.owner.hand.append(card)
			ctx.owner.hand_changed.emit()
			ctx.owner.discard_changed.emit()
			break
