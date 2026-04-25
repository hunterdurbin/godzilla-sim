extends CardEffect
## EBP04-089: Inherited Life - Strategy Rank 1 (White)
##
## Do not move this to your discard pile at the beginning of your start phase.
## <Your Turn> When you decrease your Monster card's <Rage>, put them underneath
## this. On the 15th card <Destroy> all of your opponent's battle cards. On the
## 22nd card your opponent discards their entire hand. On the 30th card you win
## the game.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: Self-anti-discard rule text — NOT the <Base> keyword (12.9).
##   Card stays in play across start phases but is not subject to Base-specific
##   interactions (e.g., not destroyed by invasion to zones 6-8 per 12.9.2).
## Interactions: None
## Implementation notes: <Rage> is a counter on the monster, not a physical card.
##   To "put them underneath this" we spawn RAGE-MARKER token placeholders — one
##   per point of rage decrease — and stack them under this strategy. The markers
##   carry the TOKEN trait so they never enter the deck or discard pile.

const RAGE_MARKER_ID := "RAGE-MARKER"


func get_bot_tags() -> Array[String]:
	return ["win_condition"]


func prevents_self_start_phase_discard(_ctx: EffectContext) -> bool:
	return true


func _find_own_strategy_zone(ctx: EffectContext) -> int:
	var self_id: String = ctx.card_data.get("id", "")
	for i in range(ctx.owner.strategy_zones.size()):
		if ctx.owner.strategy_zones[i].get("id", "") == self_id:
			return i
	return -1


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# Only trigger on own turn when rage decreases
	if ctx.is_opponent_turn():
		return
	var delta := old_rage - new_rage
	if delta <= 0:
		return

	var strategy_idx := _find_own_strategy_zone(ctx)
	if strategy_idx < 0:
		return

	var count_before: int = ctx.effect_handler.get_cards_under_strategy_top(ctx.owner, strategy_idx).size()

	# Spawn one RAGE-MARKER token placeholder per rage point lost and stack
	# them under this strategy. Rage isn't a real card, so we fabricate markers
	# rather than pulling from the discard pile.
	var template: Dictionary = CardData.get_card_by_id(RAGE_MARKER_ID)
	if template.is_empty():
		push_warning("EBP04-089: RAGE-MARKER card data not found")
		return
	for _i in range(delta):
		var marker: Dictionary = template.duplicate()
		ctx.effect_handler.place_card_under_strategy_zone(ctx.owner, marker, strategy_idx)

	var count_after: int = ctx.effect_handler.get_cards_under_strategy_top(ctx.owner, strategy_idx).size()

	# Check milestones crossed
	for milestone in [15, 22, 30]:
		if count_before < milestone and count_after >= milestone:
			await _trigger_milestone(ctx, milestone)


func _trigger_milestone(ctx: EffectContext, milestone: int) -> void:
	match milestone:
		15:
			ctx.effect_handler.log_message.emit(tr("STR_EFF_EBP04_089_MILESTONE_15"))
			var zones_to_destroy: Array[int] = ctx.opponent.get_occupied_zone_indices()
			if not zones_to_destroy.is_empty():
				await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
		22:
			ctx.effect_handler.log_message.emit(tr("STR_EFF_EBP04_089_MILESTONE_22"))
			while not ctx.opponent.hand.is_empty():
				var card := ctx.opponent.hand.pop_back() as Dictionary
				ctx.opponent.discard_pile.append(card)
			ctx.opponent.hand_changed.emit()
			ctx.opponent.discard_changed.emit()
		30:
			ctx.effect_handler.log_message.emit(tr("STR_EFF_EBP04_089_MILESTONE_30"))
			ctx.game_state.declare_winner(ctx.owner.player_id)
