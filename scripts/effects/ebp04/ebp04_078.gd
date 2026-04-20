extends CardEffect
# Crawling Calamity
# Move opp monster in areas 3-5 vertically (3→8, 4→7, 5→6).
# Does NOT destroy battle cards in zones between.


func get_bot_tags() -> Array[String]:
	return ["advances_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.monster_zone >= 3 and opponent.monster_zone <= 5


func on_enter(ctx: EffectContext) -> void:
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
		"Crawling Calamity: Opponent's monster teleported from zone %d to zone %d." % [opp_zone, target_zone])
