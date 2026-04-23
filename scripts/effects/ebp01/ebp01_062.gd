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


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_total_cp_modifier(ctx: EffectContext) -> int:
	# Only active on your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	# Check for Destoroyah battle card in zones
	var has_destoroyah: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_trait(c, CardEnums.CardTrait.DESTOROYAH))
	return 10000 if has_destoroyah else 0
