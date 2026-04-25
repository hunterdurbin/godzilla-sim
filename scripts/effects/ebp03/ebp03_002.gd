extends CardEffect
# Godzilla(2001) R2
# <Opponent's Turn> <Awakening4> Counter start: discard R5+ battle for +1 rage.
# <Awakening8> Your counter start: discard R5+ battle for +2 rage.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	if not owner.is_awakening(4):
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5):
			return true
	return false


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var is_own_turn := ctx.is_own_turn()

	# Effect 1: Opponent's turn, Awakening4, +1 rage
	if not is_own_turn and ctx.is_awakening(4):
		await _try_discard_for_rage(ctx, 1)
	# Effect 2: Your turn, Awakening8, +2 rage
	elif is_own_turn and ctx.is_awakening(8):
		await _try_discard_for_rage(ctx, 2)


func _try_discard_for_rage(ctx: EffectContext, rage_gain: int) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5),
		tr("STR_EFF_EBP03_002_PROMPT_FMT") % rage_gain,
		true
	)
	if not selected.is_empty():
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, rage_gain)
