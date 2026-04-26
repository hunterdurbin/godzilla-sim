extends CardEffect
## EBP04-043: Multi-purpose Fighting System-3 - Battle Rank 7 (Red)
## At the beginning of your counter phase, you may place a <Invade 2> card
## from your Strategy Zones under this.
## If there is a card under this card, this card gains +10,000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Find invade2 strategy cards in strategy zones
	var valid_strat: Array[int] = []
	for i in range(ctx.owner.strategy_zones.size()):
		var sz_card: Dictionary = ctx.owner.strategy_zones[i]
		if not sz_card.is_empty() and sz_card.get("invasion_icon", 0) == 2:
			valid_strat.append(i)
	if valid_strat.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_strategy_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_strat,
		tr("STR_EFF_EBP04_043_PROMPT"))
	if chosen < 0:
		return

	var strat_card: Dictionary = ctx.owner.strategy_zones[chosen]
	ctx.owner.strategy_zones[chosen] = {}
	ctx.owner.strategy_zones_changed.emit()

	# Place under this card
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		ctx.effect_handler.place_card_under_zone(ctx.owner, strat_card, my_zone)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return 0
	var cards_under: Array = ctx.effect_handler.get_cards_under_top(ctx.owner, my_zone)
	return 10000 if not cards_under.is_empty() else 0
