extends CardEffect
## EBP04-014: Godzilla (2002) - Monster Rank 2 (Blue)
## Whenever you discard a battle card from your hand, if your opponent’s <Rage> is 0,
## <Destroy> 1 of your opponent’s rank 4 or lower battle cards.
## <Opponent’s Turn> <Awakening 6> At the beginning of the counter phase, if you have 2
## or more battle cards in your zones, you may discard 1 battle card from your hand. If
## you do, this card cannot be countered by 30,000 or lower counter power this turn. (It
## will not retreat.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
	"on_phase_end": {"phase": CardEnums.GamePhase.END, "own_turn": false},
	"on_hand_card_discarded": {"card_type": "battle"},
}

var _counter_prevention_threshold: int = 0


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func prevents_counter(_ctx: EffectContext, total_cp: int) -> bool:
	# "cannot be countered by 30,000 or less counter power" — Japanese clarifies
	# "(does not retreat either)" so this is full prevention, not the
	# EBP02-027 retreat-anyway immunity.
	return _counter_prevention_threshold > 0 and total_cp <= _counter_prevention_threshold


func on_phase_end(_ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	_counter_prevention_threshold = 0


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_awakening(6):
		return
	if ctx.owner.get_battle_card_zone_indices().size() < 2:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return CardUtils.is_battle(card),
		tr("STR_EFF_EBP04_014_PROMPT"),
		true)
	if not selected.is_empty():
		_counter_prevention_threshold = 30000


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	if ctx.opponent_has_rage():
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
