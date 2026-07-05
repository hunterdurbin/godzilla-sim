extends CardEffect

## EBP02-067: M.O.G.U.E.R.A. - Battle Rank 8 (Green)
## If your opponent has a <《Godzilla》> card in their zones, this card gains +5000
## counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


## CP modifier is placement-independent — safe to preview while in hand.
const HAND_CP_PREVIEW := true


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# Check opponent's monster card
	var monster: Dictionary = ctx.opponent.current_monster
	if not monster.is_empty():
		if CardUtils.has_trait(monster, CardEnums.CardTrait.GODZILLA):
			return 5000

	# Check opponent's battle card zones
	var has: bool = ctx.opponent.has_zone_matching(
		func(c: Dictionary) -> bool: return CardUtils.has_trait(c, CardEnums.CardTrait.GODZILLA))
	if has:
		return 5000

	return 0
