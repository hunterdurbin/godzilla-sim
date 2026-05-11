extends CardEffect
## EBP04-078: Crawling Calamity - Strategy Rank 5 (Red)
## Move an opponent’s monster card in zones 3–5 vertically. (Move it from zone 3 to zone
## 8, from zone 4 to zone 7, or from zone 5 to zone 6. Battle cards in zones between
## them are not <Destroy>.)
##
## Tested: Yes
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
	var opp_zone: int = ctx.opponent.monster_zone
	if opp_zone < 3 or opp_zone > 5:
		return

	var target_zone: int
	match opp_zone:
		3: target_zone = 8
		4: target_zone = 7
		5: target_zone = 6
		_: return

	# teleport_monster respects EBP04-076 (Dormancy) via the
	# prevents_opponent_monster_move filter — returns false if blocked.
	var moved: bool = ctx.effect_handler.teleport_monster(ctx.opponent.player_id, target_zone)
	if not moved:
		ctx.effect_handler.log_message.emit(tr("STR_EFF_EBP04_078_BLOCKED"))
		return
	ctx.effect_handler.log_message.emit(
		tr("STR_EFF_EBP04_078_TELEPORT_FMT") % [opp_zone, target_zone])
