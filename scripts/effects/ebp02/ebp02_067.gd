extends CardEffect

## EBP02-067: M.O.G.U.E.R.A. - Battle Rank 8 (Green)
## If your opponent has a <Godzilla> card in their zones, this card gains +5000 CP.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if top.is_empty():
			continue
		var traits: Array = top.get("traits", [])
		if CardEnums.CardTrait.GODZILLA in traits:
			return 5000
	return 0
