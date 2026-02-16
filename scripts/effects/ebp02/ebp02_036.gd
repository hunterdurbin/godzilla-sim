extends CardEffect

## EBP02-036: Godzilla(1994) - Battle Rank 7 (Blue)
## At the beginning of your end phase, if this card is in a zone adjacent to your
## monster card, 1 of your opponent's monster cards with 40,000 or less threat level
## retreats back by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.END, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.END:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)
	if zone_idx not in adjacent:
		return

	var opp_tl: int = ctx.opponent.get_threat_level()
	if opp_tl <= 40000 and ctx.opponent.monster_zone > 1:
		ctx.opponent.monster_zone -= 1
		ctx.opponent.monster_changed.emit()
