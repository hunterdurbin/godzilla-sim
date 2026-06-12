class_name MonsterMover
extends EffectModule

## Effect-driven monster movement: step-by-step advance/retreat with
## per-zone crush, direct teleports, and the counter-retreat helper
## (rule 5.15.1.1). Honors advance/move blocking queries.



func advance_monster_to_zone(player_id: int, target_zone: int) -> void:
	## Advance a player's monster to the target zone one step at a time,
	## crushing battle cards in each intermediate zone (rule 11.3) and
	## collecting on_monster_advance entries per step, resolving them
	## after all movement completes (deferred, like ActionHandler).
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Godzilla's Dormancy when caller is the opponent's effect).
	# Check if monster is blocked from advancing (e.g. Biollante Rose Form)
	if h.is_monster_advance_blocked(player_id):
		return
	if h.is_opponent_monster_move_blocked(player_id):
		return
	var player := game_state.players[player_id]
	var deferred_entries: Array = []
	while player.monster_zone < target_zone:
		var from_zone: int = player.monster_zone
		player.monster_zone += 1
		player.monster_changed.emit()
		deferred_entries.append_array(h.collect_monster_advance_entries(player_id, from_zone, player.monster_zone))
		if action_handler:
			await action_handler.check_crush_rule(game_state, deferred_entries)
	if not deferred_entries.is_empty():
		await resolve_deferred_entries(deferred_entries)




func retreat_monster_to_zone(player_id: int, target_zone: int) -> void:
	## Retreat a player's monster to the target zone one step at a time,
	## crushing battle cards in each intermediate zone (rule 11.3).
	## Retreat does NOT trigger on_monster_advance effects.
	## Crush/revenge effects are deferred until after all movement completes.
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Godzilla's Dormancy when caller is the opponent's effect).
	if h.is_opponent_monster_move_blocked(player_id):
		return
	var player := game_state.players[player_id]
	var deferred_entries: Array = []
	while player.monster_zone > target_zone:
		player.monster_zone -= 1
		player.monster_changed.emit()
		if action_handler:
			await action_handler.check_crush_rule(game_state, deferred_entries)
	if not deferred_entries.is_empty():
		await resolve_deferred_entries(deferred_entries)




func teleport_monster(player_id: int, target_zone: int) -> bool:
	## Move a player's monster directly to target_zone without crushing
	## intermediate-zone battle cards. Used for "move vertically" effects
	## (e.g. EBP04-078 The Slithering Disaster) and the counter-retreat helper.
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Godzilla's Dormancy). Returns true if the move happened.
	if not action_handler:
		return false
	if h.is_opponent_monster_move_blocked(player_id):
		return false
	var player := game_state.players[player_id]
	if target_zone == player.monster_zone or target_zone < 1 or target_zone > 8:
		return false
	var old_zone: int = player.monster_zone
	player.monster_zone = target_zone
	action_handler.events.monster_advanced.emit(player_id, old_zone, player.monster_zone)
	player.monster_changed.emit()
	return true




func move_monster_as_countered(player_id: int) -> void:
	## Move a player's monster as though it were countered (rule 5.15.1.1):
	## a single-step teleport to the counter-retreat zone (8→3, 7→4, 6→5).
	## Does NOT crush intermediate zones and does NOT rank up — distinct from
	## retreat_monster_to_zone (which crushes step-by-step) and force_counter
	## (which also forces a rank-up). Used for "moves as though it were
	## countered" rule wording (e.g. EBP01-077 Oxygen Destroyer).
	## Effect-driven move — blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Godzilla's Dormancy). The counter-immunity branch in
	## resolve_counter is a rule action and bypasses this helper.
	var player := game_state.players[player_id]
	var retreat_zone: int = ActionHandler.get_counter_retreat_zone(player.monster_zone)
	if retreat_zone == player.monster_zone:
		return
	teleport_monster(player_id, retreat_zone)
