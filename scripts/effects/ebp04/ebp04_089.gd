extends CardEffect
## EBP04-089: Inherited Life - Strategy Rank 1 (White)
## During your start phase, this card is not sent to the discard pile.
## <Your Turn> Whenever your monster card’s <Rage> is reduced, place that many
## <Rage> under this card.
## When you place the 15th card under this card, <Destroy> all of your opponent’s
## battle cards.
## When you place the 22nd card, your opponent discards their entire hand.
## When you place the 30th card, you win the game.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: Self-anti-discard rule text — NOT the <Base> keyword (12.9).
##   Card stays in play across start phases but is not subject to Base-specific
##   interactions (e.g., not destroyed by invasion to zones 6-8 per 12.9.2).
## Interactions: None
## Implementation notes: Rage is a resource. The rage-decrease site (reduce_rage
##   and execute_start_phase_reset) drops one RAGE-MARKER per point lost into the
##   player's transient pending_rage_markers bucket. This effect claims markers
##   from that bucket via pop_back() and stacks them under its strategy. With
##   two copies of this card in play, the first to resolve claims all available
##   markers; the second sees an empty bucket — so the resource is never
##   double-counted.

const TRIGGER_FILTERS = {
	"on_rage_changed": {"own_turn": true, "direction": "decrease"},
}


func get_bot_tags() -> Array[String]:
	return ["win_condition"]


func prevents_self_start_phase_discard(_ctx: EffectContext) -> bool:
	return true


func _find_own_strategy_zone(ctx: EffectContext) -> int:
	# Match by reference identity, not card id — two copies of this strategy
	# can share the same id but each must track its own rage stack.
	for i in range(ctx.owner.strategy_zones.size()):
		if is_same(ctx.owner.strategy_zones[i], ctx.card_data):
			return i
	return -1


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	# Turn ownership and rage-direction guards live in TRIGGER_FILTERS — by the
	# time we get here, it's the controller's turn and rage is decreasing.
	var delta := old_rage - new_rage
	var strategy_idx := _find_own_strategy_zone(ctx)
	if strategy_idx < 0:
		return

	var count_before: int = ctx.effect_handler.get_cards_under_strategy_top(ctx.owner, strategy_idx).size()

	# Claim up to `delta` rage markers from the player's pending_rage_markers
	# bucket — rage is a resource. If another effect (or another copy of this
	# card) already popped them, the bucket may be empty; just take what's left.
	var to_claim: int = mini(delta, ctx.owner.pending_rage_markers.size())
	for _i in range(to_claim):
		var marker: Dictionary = ctx.owner.pending_rage_markers.pop_back()
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
			var zones_to_destroy: Array[int] = ctx.opponent.get_battle_card_zone_indices()
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
			ctx.game_state.game_over.emit(ctx.owner.player_id, "STR_LOG_REASON_INHERITED_LIFE")
