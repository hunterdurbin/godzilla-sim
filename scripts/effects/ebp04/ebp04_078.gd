extends CardEffect
## EBP04-078: Crawling Calamity - Strategy Rank 5 (Red)
## Move your opponent's Monster card in areas 3-5 vertically. (3->8, 4->7, 5->6.
## Do not destroy battle cards in areas in between)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.monster_zone >= 3 and opponent.monster_zone <= 5


func on_enter(ctx: EffectContext) -> void:
	if ctx.effect_handler.is_opponent_monster_move_blocked(ctx.opponent.player_id):
		ctx.effect_handler.log_message.emit(tr("STR_EFF_EBP04_078_BLOCKED"))
		return

	var opp_zone: int = ctx.opponent.monster_zone
	if opp_zone < 3 or opp_zone > 5:
		return

	var target_zone: int
	match opp_zone:
		3: target_zone = 8
		4: target_zone = 7
		5: target_zone = 6
		_: return

	# Move monster without destroying intervening battle cards
	ctx.opponent.monster_zone = target_zone
	ctx.opponent.monster_changed.emit()
	ctx.effect_handler.log_message.emit(
		tr("STR_EFF_EBP04_078_TELEPORT_FMT") % [opp_zone, target_zone])
