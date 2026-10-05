extends CardEffect

## ESD04-004: Destoroyah Perfect Form - Monster Rank 4 (Blue)
## <Enter> You may discard a strategy card from your hand to decrease your
## opponent's <Rage> by 1.
## <Overwhelm> If you have a 「Godzilla vs. Destoroyah」 card in play, add
## +10,000 counter power to your total.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: EBP01-062 / EBP01-065 / EBP04-083 (Godzilla vs. Destoroyah)
## Implementation notes: "In play" for a strategy card = a strategy zone.
##   <Overwhelm> = ctx.is_overwhelm() (own monster zone >= opponent's).


const GVD_NAME := "Godzilla vs. Destoroyah"


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_rage() and owner.hand.any(CardUtils.is_strategy)


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		CardUtils.is_strategy,
		tr("STR_EFF_ESD04_004_PROMPT"),
		true)
	if not selected.is_empty():
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if not ctx.is_overwhelm():
		return 0
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("name", "") == GVD_NAME:
			return 10000
	return 0
