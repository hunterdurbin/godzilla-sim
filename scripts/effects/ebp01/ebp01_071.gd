extends CardEffect

## EBP01-071: Giant Condor - Battle Rank 5 (White)
## If this card is in the same column as your opponent's monster card, this card gains
## +5000 counter power.
## When your opponent's <Rage> is increased, <Destroy> this card.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := _find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) in opp_columns:
		return 5000
	return 0


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# This triggers when ANY player's rage changes. We need opponent's rage increase.
	# The rage_changed trigger is called on this card for its owner's rage changes.
	# To detect opponent's rage increase, we check from the opponent's perspective.
	# However, trigger_rage_changed is called per-player for that player's cards.
	# So this card's on_rage_changed fires when the OWNER's rage changes.
	# We need to self-destruct when the OPPONENT's rage increases.
	# This requires a different trigger mechanism (opponent_rage_changed).
	# For now, we approximate: if owner's rage hasn't changed but opponent's has,
	# we can't detect it here. This is a system limitation.
	pass


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
