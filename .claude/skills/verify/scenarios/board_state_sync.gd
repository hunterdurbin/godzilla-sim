extends RefCounted
## Board/state sync: drives real actions (v.act) and engine primitives on P1
## and checks after each that the rendered hand and zones match PlayerState
## (v.check_sync). Run it after any change to PlayerState signal emission or
## to when the board syncs from state.
##   play battle, overload, strategy, gain rage, destroy by effect,
##   evolution (deck search), monster play, invade
## Any mismatch prints "[Scenario] FAIL", so scenario.sh reports SCENARIO FAIL.
## Run: .claude/skills/verify/scenario.sh <godot> .claude/skills/verify/scenarios/board_state_sync.gd

const A := CardEnums.ActionType

var v: Node
var p0: PlayerState
var mismatches: int = 0


func run(driver: Node) -> void:
	v = driver
	p0 = v.gs.players[0]
	v.note("start hand=%d zones=%s" % [p0.hand.size(), _zone_summary()])

	# A: play a battle card into zone 3
	var c1 := _stage_hand("ESD01-008")
	await _act_and_check("A_play_battle", A.PLAY_BATTLE, {"hand_index": p0.hand.find(c1), "zone_index": 2})
	# B: overload zone 3
	var c2 := _stage_hand("ESD01-008")
	var disc := p0.discard_pile.size()
	await _act_and_check("B_overload", A.PLAY_BATTLE, {"hand_index": p0.hand.find(c2), "zone_index": 2})
	v.note("B discard %d->%d" % [disc, p0.discard_pile.size()])
	# C: strategy play
	var s := _stage_hand("EBP04-089")
	await _act_and_check("C_strategy", A.PLAY_STRATEGY, {"hand_index": p0.hand.find(s)})
	v.note("C strategy0=%s" % CardUtils.base_id(p0.strategy_zones[0]))
	# D: gain rage
	var r := _stage_hand("ESD01-008")
	var rage := p0.rage
	await _act_and_check("D_gain_rage", A.GAIN_RAGE, {"hand_index": p0.hand.find(r)})
	v.note("D rage %d->%d" % [rage, p0.rage])
	# E: destroy zone 3 by effect
	var zones: Array[int] = [2]
	v.h.destroy_zones(p0, zones)
	await v.wait(1.0)
	v.close_overlays()
	await _check("E_destroy")
	# F: evolution in zone 5 (deck search answered through the input port)
	v.ed.add_to_zone(0, 4, v.ed.mint_card("ESD02-007"), true)
	var target: Dictionary = v.ed.mint_card("ESD02-007")
	v.ed.add_to_deck(0, target, 0)
	await v.wait(0.5)
	v.h.perform_evolution(0, 4)  # not awaited: the search prompt waits
	await v.wait(1.5)
	v.shot("F1_evolve_search")
	v.tm.player_input.resolve_deck_search(target)
	await v.wait(1.0)
	v.close_overlays()
	v.note("F zone5 stack=%d top=%s" % [p0.get_zone_stack(4).size(), CardUtils.base_id(p0.get_zone_top_card(4))])
	await _check("F_evolve")
	# G: monster play (rank 2 from hand)
	var rank2_id := ""
	for m in p0.monster_deck:
		if m.get("rank", 0) == 2:
			rank2_id = CardUtils.base_id(m)
			break
	if rank2_id != "":
		var mon := _stage_hand(rank2_id)
		await _act_and_check("G_play_monster", A.PLAY_MONSTER, {"hand_index": p0.hand.find(mon)})
		v.note("G monster=%s stack=%d" % [CardUtils.base_id(p0.current_monster), p0.monster_stack.size()])
	else:
		v.note("G skipped: no rank-2 monster in the monster deck")
	# H: invade
	var inv := _stage_hand("ESD01-008")
	var zone_before: int = p0.monster_zone
	await _act_and_check("H_invade", A.INVADE, {"hand_index": p0.hand.find(inv)})
	v.note("H monster_zone %d->%d" % [zone_before, p0.monster_zone])
	for line in v.log_tail(8):
		v.note("log: " + line)
	v.note("RESULT mismatches=%d" % mismatches)
	if mismatches > 0:
		v.note("FAIL %d board/state mismatches" % mismatches)


func _stage_hand(id: String) -> Dictionary:
	var card: Dictionary = v.ed.mint_card(id)
	v.ed.add_to_hand(0, card)
	return card


func _act_and_check(label: String, action: int, params: Dictionary) -> void:
	await v.act(action, params)
	await _check(label)


func _check(label: String) -> void:
	if not await v.check_sync(0, label):
		mismatches += 1


func _zone_summary() -> String:
	var out: Array[String] = []
	for i in range(8):
		out.append(str(p0.get_zone_stack(i).size()))
	return ",".join(out)
