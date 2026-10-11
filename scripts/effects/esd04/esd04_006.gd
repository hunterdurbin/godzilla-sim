extends CardEffect

## ESD04-006: Godzilla vs. Destoroyah - Strategy Rank 5 (Blue)
## <Opponent's Turn> For each battle card with <《Destoroyah》> in your zones,
## your monster card gains +5000 threat. (Cards stacked through evolution count
## as 1 card.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: ESD04-004 (Godzilla vs. Destoroyah in play)
## Implementation notes: Each zone's TOP card is counted, so an evolution
##   stack counts once.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.is_own_turn():
		return 0
	return 5000 * ctx.owner.count_zones_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_trait(c, CardEnums.CardTrait.DESTOROYAH))
