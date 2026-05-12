extends CardEffect

## EBP02-027: Biollante Plant Beast Form - Monster Rank 3 (Blue)
## <Opponent’s Turn> <Awakening6> If your opponent has a strategy card in play, this
## card cannot be countered by 40,000 or lower counter power. Instead, it only moves as
## though it were countered. (Do not play the next Monster Card from your monster deck.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_immunity_threshold(ctx: EffectContext) -> int:
	# Only active during opponent's turn
	if ctx.is_own_turn():
		return 0
	# Awakening6: owner's monster must be in zone 6 or higher
	if not ctx.is_awakening(6):
		return 0
	# Opponent (the turn player / defender) must have a strategy card in play
	var has_strategy: bool = false
	for sz_card in ctx.opponent.strategy_zones:
		if not sz_card.is_empty():
			has_strategy = true
			break
	if not has_strategy:
		return 0
	return 40000
