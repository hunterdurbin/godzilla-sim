extends CardEffect
# Godzilla(2001) R3
# <Burst2>
# <Awakening8> Your counter start: discard R5+ battle for +2 rage, then Destroy all opponent R6-.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	if not owner.is_awakening(8):
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5):
			return true
	return false


func get_burst_rank() -> int:
	return 2


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_awakening(8):
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5),
		tr("STR_EFF_EBP03_003_PROMPT"),
		true
	)
	if not selected.is_empty():
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 2)

		# Destroy all opponent R6 or lower battle cards
		var zones_to_destroy: Array[int] = ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 6)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
