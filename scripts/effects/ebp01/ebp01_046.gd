extends CardEffect

## EBP01-046: MBT-MB92 - Battle Rank 3 (Blue)
## You may have any number of this card in your deck.
## <Awakening6> This card gains +3000 counter power. (Active if your monster card is in
## zone 6 or beyond.)
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
	if ctx.is_awakening(6):
		return 3000
	return 0
