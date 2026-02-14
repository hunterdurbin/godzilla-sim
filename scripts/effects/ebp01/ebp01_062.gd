extends CardEffect

## EBP01-062: Godzilla vs. Destoroyah - Strategy Rank 3 (Blue)
## <Your Turn> If you have a <Destoroyah> battle card in your zones, increase your
## total counter power by +10,000.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Strategy CP modifier, checked by EffectHandler.get_counter_power_modifier


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_total_cp_modifier(ctx: EffectContext) -> int:
	# Only active on your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	# Check for Destoroyah battle card in zones
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("card_type") == CardEnums.CardType.BATTLE:
			if CardEnums.CardTrait.DESTOROYAH in zone_card.get("traits", []):
				return 10000
	return 0
