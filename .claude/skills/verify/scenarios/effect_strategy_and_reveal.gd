extends RefCounted
## Example scenario (copy it for new checks). Stages state with v.ed
## (BoardEditor), fires engine entry points on v.h, screenshots, reads the log.
##   A: EFC01-005 reveal overlay -> Fest card to hand, rest to discard
##   B: a strategy played by an effect (play_strategy_from_effect) logs a play
## Run: .claude/skills/verify/scenario.sh <godot> .claude/skills/verify/scenarios/effect_strategy_and_reveal.gd


func run(v: Node) -> void:
	var p0: PlayerState = v.gs.players[0]

	# --- A: EFC01-005 ---
	v.ed.set_strategy(0, 0, v.ed.mint_card("EFC01-005"))
	v.ed.add_to_deck(0, v.ed.mint_card("EBP01-011"), 0)  # a <Fest> card on top
	var hand_before := p0.hand.size()
	var disc_before := p0.discard_pile.size()
	v.h.dispatcher.trigger_monster_played(0, {}, p0.current_monster)  # queues to standby
	v.h.check_timing.resolve()  # not awaited: the overlay waits
	await v.wait(1.5)
	v.shot("a1_reveal_overlay")
	v.close_overlays()
	await v.wait(1.0)
	v.shot("a2_after_close")
	v.note("A hand %d->%d discard %d->%d" % [hand_before, p0.hand.size(), disc_before, p0.discard_pile.size()])
	for line in v.log_tail(2):
		v.note("A log: " + line)

	# --- B: strategy played by an effect, from the discard pile ---
	var strat: Dictionary = v.ed.mint_card("EBP04-089")  # Inherited Life: no <Enter> prompt
	v.ed.add_to_discard(0, strat)
	var idx: int = await v.h.play_strategy_from_effect(0, strat)
	await v.wait(1.0)
	v.close_overlays()
	await v.wait(0.5)
	v.shot("b_strategy_play")
	v.note("B zone=%d turn_placed=%d still_in_discard=%s" % [
		idx, p0.strategy_zone_turn_placed[idx] if idx >= 0 else -1, p0.discard_pile.has(strat)])
	for line in v.log_tail(1):
		v.note("B log: " + line)
