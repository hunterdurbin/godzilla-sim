extends CardEffect
# Mechagodzilla(1974) (Battle R4)
# At the beginning of your counter phase, if this card is in a zone adjacent to your
# monster card, you may discard all the cards in your hand. If you do, for the rest of
# the turn, this card gains +1000 counter power for each card discarded this way.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}

var _bonus_cp: int = 0


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func serialize_state() -> Dictionary:
	if _bonus_cp == 0:
		return {}
	return {"bonus_cp": _bonus_cp}


func restore_state(data: Dictionary) -> void:
	_bonus_cp = int(data.get("bonus_cp", 0))


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	_bonus_cp = 0
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	if monster_idx not in get_adjacent_zones(zone_idx):
		return

	if ctx.owner.hand.is_empty():
		return

	# Ask if they want to discard all hand
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card): return true,
		tr("STR_EFF_EBP03_032_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	# The selected card is already discarded by select_hand_card. Discard the rest.
	var discarded_count: int = 1 + ctx.owner.hand.size()
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, 0)
	_bonus_cp = discarded_count * 1000


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_opponent_turn():
		return 0
	return _bonus_cp
