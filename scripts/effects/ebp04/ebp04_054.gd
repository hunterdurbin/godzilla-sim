extends CardEffect
## EBP04-054: Destoroyah Perfect Form - Battle Rank 8 (Blue)
## For each Strategy Card you have in play, this card gains 5000 counter
## power.
## For each strategy card your opponent has in play, this card loses 5000
## counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var own_strat: int = 0
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty():
			own_strat += 1

	var opp_strat: int = 0
	for sz_card in ctx.opponent.strategy_zones:
		if not sz_card.is_empty():
			opp_strat += 1

	return own_strat * 5000 - opp_strat * 5000
