class_name MonsterMover
extends EffectModule

## The monster-movement module (GLOSSARY: Advance): the only engine code
## that moves a monster, i.e. writes `PlayerState.monster_zone` during a
## match. (State restore/simulation — state_codec, game_serializer, bot
## planning, deck analysis — and the F4 board editor dev tool write it
## outside play.) Every move goes through one of its operations:
##   * `advance` / `advance_to_zone` — step by step; per step the Crush rule
##     (11.3) runs through CheckTiming and the "when your monster advances"
##     entries are collected. Only an advance `from_invasion` (5.13) collects
##     <When invading> entries (12.3) and can move past zone 8 for victory
##     through invasion (5.13.1.1.2); any other advance stops at zone 8.
##   * `retreat_to_zone` — step by step with per-step Crush; no advance
##     triggers.
##   * `teleport` — straight to a zone without crossing the zones between;
##     only the destination is crushed. `counter_retreat` (5.15.1.1) is built
##     on it.
##   * `place_at_start` — the starting zone at match setup (no move, no
##     events).
## Collected entries are appended to the caller's array; the caller submits
## them to CheckTiming when its movement is done. Blocking checks (advance
## blocked, e.g. Biollante Rose Form; opponent-move blocked, EBP04-076) are
## the CALLERS' job — the operations themselves always move.
##
## The effect-facing entry points at the bottom (advance_monster_to_zone,
## …) are such callers: they apply the blocking checks, then use the
## operations above.
##
## Every move emits GameEvents.monster_advanced(player, from, to) — per
## step for advance and retreat, once for a teleport; `to < from` is a
## move back. `monster_changed` follows each step, except during an
## invasion, whose resolver emits it once after movement.


# --- Operations ---


func place_at_start(player_id: int, zone: int) -> void:
	## Put the monster in its starting zone at match setup. Not a move: no
	## events, no Crush.
	game_state.players[player_id].monster_zone = zone


func advance(player_id: int, steps: int, from_invasion: bool, entries: Array) -> bool:
	## Advance up to `steps` zones, one at a time. Per step: emit the events,
	## collect <When invading> (only `from_invasion`) and the "monster
	## advances" entries into `entries`, then run Crush (its entries join
	## `entries` too). A non-invasion advance stops at zone 8. An invasion
	## at zone 8 moves past it when the opponent's zone 8 holds no battle
	## card — victory through invasion (5.13.1.1.2), returned as true — and
	## otherwise stops.
	## Every step emits GameEvents.monster_advanced. An invasion emits the
	## monster's `monster_changed` only on the victory step — the invasion
	## resolver emits it once after movement.
	var player := game_state.players[player_id]
	for _step in range(steps):
		if player.monster_zone >= 8:
			if not from_invasion:
				return false
			var opponent := game_state.get_opponent(player_id)
			if opponent.zone_has_battle_card(7):  # Zone 8 = index 7
				return false
			var last_zone: int = player.monster_zone
			player.monster_zone = 9  # Past zone 8
			_emit_advanced(player_id, last_zone, player.monster_zone)
			player.monster_changed.emit()
			entries.append_array(h.collect_when_invading_entries(player_id, last_zone, player.monster_zone))
			return true
		var old_zone: int = player.monster_zone
		player.monster_zone += 1
		_emit_advanced(player_id, old_zone, player.monster_zone)
		if from_invasion:
			entries.append_array(h.collect_when_invading_entries(player_id, old_zone, player.monster_zone))
		else:
			player.monster_changed.emit()
		entries.append_array(h.collect_monster_advance_entries(player_id, old_zone, player.monster_zone))
		if action_handler:
			check_timing.check_crush_rule(entries)
	return false


func advance_to_zone(player_id: int, target_zone: int, entries: Array) -> void:
	## Advance (not from an invasion) until the monster reaches `target_zone`
	## or zone 8. See `advance`.
	var steps: int = target_zone - game_state.players[player_id].monster_zone
	if steps > 0:
		advance(player_id, steps, false, entries)


func retreat_to_zone(player_id: int, target_zone: int, entries: Array) -> void:
	## Retreat one zone at a time down to `target_zone`, running Crush per
	## step (its entries join `entries`). Retreating is not advancing: no
	## advance triggers. Emits GameEvents.monster_advanced (a downward
	## move) and `monster_changed` per step.
	var player := game_state.players[player_id]
	while player.monster_zone > target_zone:
		var old_zone: int = player.monster_zone
		player.monster_zone -= 1
		_emit_advanced(player_id, old_zone, player.monster_zone)
		player.monster_changed.emit()
		if action_handler:
			check_timing.check_crush_rule(entries)


func teleport(player_id: int, target_zone: int) -> void:
	## Move straight to `target_zone` without crossing the zones between.
	## Only the destination is crushed, right away — Crush is an interrupt
	## rule action (11.1.2.1) — and the abilities it triggers enter standby
	## (10.6.2). Crush checks the moved player only: no other monster moved,
	## and no entry can put a card in a monster's zone. Emits
	## GameEvents.monster_advanced, then `monster_changed`.
	var player := game_state.players[player_id]
	var old_zone: int = player.monster_zone
	player.monster_zone = target_zone
	_emit_advanced(player_id, old_zone, player.monster_zone)
	player.monster_changed.emit()
	check_timing.crush_now(player_id)


func counter_retreat(player_id: int) -> bool:
	## Counter retreat (5.15.1.1): only zones 6-8 move back (8→3, 7→4, 6→5),
	## as a teleport (same events and destination Crush). Returns true if
	## the monster moved.
	var player := game_state.players[player_id]
	var retreat_zone: int = ActionHandler.get_counter_retreat_zone(player.monster_zone)
	if retreat_zone == player.monster_zone:
		return false
	teleport(player_id, retreat_zone)
	return true


func _emit_advanced(player_id: int, from_zone: int, to_zone: int) -> void:
	if h.events:
		h.events.monster_advanced.emit(player_id, from_zone, to_zone)


# --- Effect-facing entry points (callers: blocking checks, then an operation) ---


func advance_monster_to_zone(player_id: int, target_zone: int) -> void:
	## Effect-driven advance to `target_zone`. Blocked by advance blocking
	## (e.g. Biollante Rose Form) and by `prevents_opponent_monster_move`
	## (e.g. EBP04-076 Godzilla's Dormancy when the caller is the opponent's
	## effect). Emits GameEvents.monster_advanced and `monster_changed` per
	## step (see `advance`).
	if h.is_monster_advance_blocked(player_id):
		return
	if h.is_opponent_monster_move_blocked(player_id):
		return
	var entries: Array = []
	advance_to_zone(player_id, target_zone, entries)
	check_timing.submit(entries)


func retreat_monster_to_zone(player_id: int, target_zone: int) -> void:
	## Effect-driven retreat to `target_zone`. Blocked by
	## `prevents_opponent_monster_move` (e.g. EBP04-076). Emits
	## GameEvents.monster_advanced and `monster_changed` per step (see
	## `retreat_to_zone`).
	if h.is_opponent_monster_move_blocked(player_id):
		return
	var entries: Array = []
	retreat_to_zone(player_id, target_zone, entries)
	check_timing.submit(entries)


func teleport_monster(player_id: int, target_zone: int) -> bool:
	## Effect-driven "move vertically" (e.g. EBP03-068 Godzilla Flies,
	## EBP04-078 The Slithering Disaster): a teleport to a zone 1-8 other
	## than the current one. Blocked by `prevents_opponent_monster_move`
	## (e.g. EBP04-076). Returns true if the move happened.
	if not action_handler:
		return false
	if h.is_opponent_monster_move_blocked(player_id):
		return false
	var player := game_state.players[player_id]
	if target_zone == player.monster_zone or target_zone < 1 or target_zone > 8:
		return false
	teleport(player_id, target_zone)
	return true


func move_monster_as_countered(player_id: int) -> void:
	## Move a player's monster as though it were countered (rule 5.15.1.1):
	## the counter retreat without a rank-up — distinct from
	## retreat_monster_to_zone (which crushes step by step) and force_counter
	## (which also forces a rank-up). Used for "moves as though it were
	## countered" wording (e.g. EBP01-077 Oxygen Destroyer). Blocked by
	## `prevents_opponent_monster_move` (e.g. EBP04-076); the counter phase's
	## own retreat is a rule action and is not.
	if not action_handler:
		return
	if h.is_opponent_monster_move_blocked(player_id):
		return
	counter_retreat(player_id)
