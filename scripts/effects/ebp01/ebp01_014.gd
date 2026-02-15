extends CardEffect

## EBP01-014: Godzilla(Fest Godzilla) - Monster Rank 4
## <Opponent's Turn> <Awakening4> If you have 2 or more battle cards in your zones,
## all of your opponent's rank 5 or lower battle cards cannot engage with this card.
## (Their counter power is not included in the total during the counter phase.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_engagement_restriction(ctx: EffectContext) -> int:
	if _should_restrict(ctx):
		return 5
	return -1


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
		if ctx.owner.zone_has_cards(i):
			count += 1
	return count >= 2
