extends CardEffect

## EBP01-014: Godzilla(Fest Godzilla) - Monster Rank 4
## <Opponent's Turn> <Awakening4> If you have 2 or more battle cards in your zones,
## all of your opponent's rank 5 or lower battle cards cannot engage with this card.
## (Their counter power is not included in the total during the counter phase.)
##
## NOTE: This effect modifies opponent's battle card engagement. The get_engagement_restriction
## method returns the max rank of cards that cannot engage, for the system to query.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	# Implemented as a threat modifier workaround: if conditions are met,
	# opponent's R5 or lower cards' CP shouldn't count.
	# The proper implementation requires system-level engagement filtering.
	# For now, this is a marker — the effect_handler should check
	# the monster's engagement restrictions during counter resolution.
	return 0


func _should_restrict(ctx: EffectContext) -> bool:
	# Opponent's turn only
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return false
	# Awakening4
	if ctx.owner.monster_zone < 4:
		return false
	# 2+ battle cards in zones
	var count: int = 0
	for i in range(8):
		if not ctx.owner.is_zone_empty(i):
			count += 1
	return count >= 2
