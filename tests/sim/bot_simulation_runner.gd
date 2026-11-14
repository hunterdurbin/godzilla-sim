extends Node

## Runs N bot-vs-bot games headlessly and prints summary statistics.
## Usage: godot --headless --path . tests/sim/BotSimulationRunner.tscn \
##          [-- --games=N --seed=S --p1=HARD --p2=KAIJU --deck1="Name" --deck2="Name"]
## Command-line args override the exports below (difficulty by enum name).

@export var num_games: int = 200
@export var p1_difficulty: BotConfig.Difficulty = BotConfig.Difficulty.HARD
@export var p2_difficulty: BotConfig.Difficulty = BotConfig.Difficulty.HARD
@export var p1_deck_name: String = "ESD01 Starter"
@export var p2_deck_name: String = "ESD02 Starter"
@export var base_seed: int = 0
## Record a replay JSON per game for the replay-stats tuning loop
## (scripts/tools/replay_stats/). Off by default: recording consumes no RNG,
## but baselines stay provably byte-identical this way.
@export var record_replays: bool = false
## Outside user://replays/<version>/recent/ so prune_recent never eats them.
@export var replay_dir: String = "user://replays/sim/"

var _games_completed: int = 0
var _results: Array[Dictionary] = []
var _current_turn_manager: TurnManager
var _current_bots: Array = [] # [BotPlayer, BotPlayer]
var _game_running: bool = false
var _recorder: ReplayRecorder = null
## base card id -> number of times one of its abilities started resolving,
## summed over every game. Printed as the [SimEffects] line.
var _effect_counts: Dictionary[String, int] = {}
var _effect_counts_available: bool = false


func _ready() -> void:
	# Uncap frame rate for maximum simulation speed
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 10000
	_apply_cmdline_overrides()
	if base_seed == 0:
		base_seed = randi()
	print("=== Bot Simulation Starting (%d games, seed=%d) ===" % [num_games, base_seed])
	print("P1: %s  |  P2: %s" % [
		BotConfig.Difficulty.keys()[p1_difficulty],
		BotConfig.Difficulty.keys()[p2_difficulty]])
	_start_next_game()


func _apply_cmdline_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		var key: String = arg.get_slice("=", 0)
		var value: String = arg.substr(key.length() + 1)
		match key:
			"--games": num_games = int(value)
			"--seed": base_seed = int(value)
			"--p1": p1_difficulty = _difficulty(value, p1_difficulty)
			"--p2": p2_difficulty = _difficulty(value, p2_difficulty)
			"--deck1": p1_deck_name = value
			"--deck2": p2_deck_name = value
			"--record-replays": record_replays = true
			_: push_warning("BotSimulationRunner: unknown arg %s" % arg)


func _select_deck_file(player_id: int, path: String) -> void:
	var full: String = path if path.begins_with("res://") or path.is_absolute_path() else "res://" + path
	var text := FileAccess.get_file_as_string(full)
	if text.is_empty():
		push_error("BotSimulationRunner: cannot read deck file %s" % full)
		return
	var data: Dictionary = DecklistManager.parse_decklist_text(text)
	DecklistManager.set_player_deck_from_entries(player_id, full.get_file().get_basename(), data["monster"], data["main"])


func _difficulty(value: String, fallback: BotConfig.Difficulty) -> BotConfig.Difficulty:
	var idx: int = BotConfig.Difficulty.keys().find(value.to_upper())
	if idx < 0:
		push_warning("BotSimulationRunner: unknown difficulty %s" % value)
		return fallback
	return idx as BotConfig.Difficulty


func _start_next_game() -> void:
	# Break the previous match's reference cycles so each game's engine graph
	# can be freed (otherwise every game leaks until process exit). Runs via
	# call_deferred, so the finished game's coroutine stack has unwound.
	if _current_turn_manager:
		_current_turn_manager.teardown()
		_current_turn_manager = null
	_current_bots = []

	if _games_completed >= num_games:
		_print_summary()
		get_tree().quit()
		return

	seed(base_seed + _games_completed)

	# Set up decks via DecklistManager. "@<path>" loads a .deck file directly
	# (res:// or absolute, e.g. a committed tests/sim/decks/ coverage deck);
	# anything else is a decklist name from the user's decklists dir.
	for i in range(2):
		var deck_name: String = p1_deck_name if i == 0 else p2_deck_name
		if deck_name.begins_with("@"):
			_select_deck_file(i, deck_name.substr(1))
		elif not deck_name.is_empty():
			DecklistManager.select_deck_for_player(i, deck_name)

	# Create TurnManager and set up the game
	_current_turn_manager = TurnManager.new()
	_current_turn_manager.setup(CardData)

	# Create two bots
	var bot1 := BotPlayer.new()
	bot1.config = BotConfig.from_difficulty(p1_difficulty)
	bot1.config.action_delay = 0.0
	bot1.bot_player_id = 0
	bot1.game_state = _current_turn_manager.game_state
	bot1.rules_engine = _current_turn_manager.rules_engine
	bot1.turn_manager = _current_turn_manager
	bot1.action_handler = _current_turn_manager.action_handler
	bot1.effect_handler = _current_turn_manager.action_handler.effect_handler
	bot1.scene_tree = get_tree() # Needed for async signal timing

	var bot2 := BotPlayer.new()
	bot2.config = BotConfig.from_difficulty(p2_difficulty)
	bot2.config.action_delay = 0.0
	bot2.bot_player_id = 1
	bot2.game_state = _current_turn_manager.game_state
	bot2.rules_engine = _current_turn_manager.rules_engine
	bot2.turn_manager = _current_turn_manager
	bot2.action_handler = _current_turn_manager.action_handler
	bot2.effect_handler = _current_turn_manager.action_handler.effect_handler
	bot2.scene_tree = get_tree()

	_current_bots = [bot1, bot2]

	# Per-card resolution counts for run_sim_diff's [SimEffects] line. A base
	# tree older than GameEvents.effect_resolving reports no counts.
	var bus: GameEvents = _current_turn_manager.events
	if bus.has_signal("effect_resolving"):
		_effect_counts_available = true
		bus.connect("effect_resolving", _on_effect_resolving)

	# Instant confirmation — resolve synchronously (no await, no frame wait).
	# Must be connected BEFORE bot handlers so it fires first. Uses a named
	# method: a lambda capturing `pin` would store a strong self-reference on
	# the pin's own signal and leak one SignalPlayerInput per game.
	var pin: SignalPlayerInput = _current_turn_manager.player_input
	pin.confirmation_requested.connect(_on_sim_confirmation)

	# Connect signals for both bots (same pattern as game_session.setup_bot)
	for bot in _current_bots:
		bot.player_input = pin
		_current_turn_manager.awaiting_player_action.connect(bot._on_awaiting_action)
		pin.monster_rankup_requested.connect(bot._on_monster_rankup_requested)
		pin.choice_requested.connect(bot._on_choice_requested)
		pin.hand_discard_requested.connect(bot._on_hand_discard_requested)
		pin.deck_search_requested.connect(bot._on_deck_search_requested)
		pin.deck_arrange_requested.connect(bot._on_deck_arrange_requested)
		pin.card_select_requested.connect(bot._on_card_select_requested)
		pin.hand_card_selection_requested.connect(bot._on_hand_card_selection_requested)
		pin.zone_target_requested.connect(bot._on_zone_target_requested)
		pin.strategy_target_requested.connect(bot._on_strategy_target_requested)
		pin.cards_revealed_requested.connect(bot._on_cards_revealed_requested)

	# Analyze decks / init combos
	bot1.analyze_deck()
	bot2.analyze_deck()

	# Connect game_ended to record result
	_current_turn_manager.game_ended.connect(_on_game_ended)

	# Safety: cap at 50 turns to avoid infinite loops
	_current_turn_manager.turn_started.connect(_on_turn_started)

	if record_replays:
		_recorder = ReplayRecorder.new()
		var deck_names: Array[String] = [p1_deck_name, p2_deck_name]
		_recorder.start(_current_turn_manager.game_state, base_seed + _games_completed, "sim",
				"%s_vs_%s" % [BotConfig.Difficulty.keys()[p1_difficulty], BotConfig.Difficulty.keys()[p2_difficulty]],
				deck_names, get_tree())
		_current_turn_manager.log_message.connect(_recorder.on_log_message)
		# Effect-layer tokens (played_*, rage_gained, invaded, effect_*) are
		# emitted on the effect handler, not the TurnManager.
		_current_turn_manager.effect_handler.log_message.connect(_recorder.on_log_message)
		# Counter tokens are synthesized from GameEvents in live games
		# (game_board._on_counter_*) — mirror that here for threat-swing stats.
		var ev: GameEvents = _current_turn_manager.events
		ev.counter_succeeded.connect(func(pid: int, cp: int, threat: int, rage_t: int, eff_t: int) -> void:
			if _recorder:
				_recorder.on_log_message(GameLog.counter_succeeded(pid, cp, threat, rage_t, eff_t)))
		ev.counter_failed.connect(func(pid: int, cp: int, threat: int, rage_t: int, eff_t: int) -> void:
			if _recorder:
				_recorder.on_log_message(GameLog.counter_failed(pid, cp, threat, rage_t, eff_t)))
		_current_turn_manager.sub_phase_changed.connect(_recorder.on_phase_boundary)
		_current_turn_manager.turn_started.connect(func(_pid: int) -> void:
			if _recorder:
				_recorder.on_state_changed())

	_game_running = true
	_current_turn_manager.start_game(_games_completed % 2) # Alternate starting player


func _on_sim_confirmation(_prompt: String, _setting: String) -> void:
	if _current_turn_manager and _current_turn_manager.player_input:
		_current_turn_manager.player_input.resolve_confirmation()


func _on_turn_started(player_id: int) -> void:
	if _game_running:
		_print_turn_trace(player_id)
	if _current_turn_manager.game_state.turn_number > 50:
		print("[Sim] Game %d exceeded 50 turns — forcing draw" % (_games_completed + 1))
		_record_result(-1, "Turn limit exceeded")
		_current_turn_manager.is_game_over = true
		_game_running = false
		_start_next_game.call_deferred()


## One [SimTurn] line per turn start: both players' zone, monster (base id
## and rank), rage and hand size. run_sim_diff.sh copies this runner into the
## base worktree, so base and head print the same format and the first
## differing line shows where a seed-matched game split.
func _print_turn_trace(active_player_id: int) -> void:
	var gs: GameState = _current_turn_manager.game_state
	var sides: Array[String] = []
	for i in range(2):
		var p: PlayerState = gs.players[i]
		sides.append("p%d z%d %s r%d rage=%d hand=%d" % [i + 1, p.monster_zone,
				CardUtils.base_id(p.current_monster), p.current_monster.get("rank", 0),
				p.rage, p.hand.size()])
	print("[SimTurn] game=%d t=%d active=p%d | %s" % [_games_completed + 1,
			gs.turn_number, active_player_id + 1, " | ".join(sides)])


func _on_game_ended(winner_id: int, reason: String) -> void:
	_record_result(winner_id, reason)
	_game_running = false
	_start_next_game.call_deferred()


func _record_result(winner_id: int, reason: String) -> void:
	var gs: GameState = _current_turn_manager.game_state
	# Snapshot final state into combo stats
	for i in range(2):
		_current_bots[i].combo_stats["final_rank"] = gs.players[i].current_monster.get("rank", 0)
		_current_bots[i].combo_stats["final_zone"] = gs.players[i].monster_zone
	if _recorder:
		var replay := _recorder.finish(winner_id, reason, _games_completed % 2)
		DirAccess.make_dir_recursive_absolute(replay_dir)
		var path := replay_dir.path_join("sim_g%03d_seed%d.json" % [_games_completed + 1, base_seed + _games_completed])
		# Saved directly (not via ReplayRecorder.save) so the recent-replays
		# pruning never touches sim output.
		var err := ReplayData.save_to_file(replay, path)
		if err != OK:
			push_warning("[Sim] Failed to save replay %s (error %d)" % [path, err])
		_recorder = null
	var result := {
		"winner": winner_id,
		"reason": reason,
		"turns": gs.turn_number,
		"p1_zone": gs.players[0].monster_zone,
		"p2_zone": gs.players[1].monster_zone,
		"p1_combo_stats": _current_bots[0].combo_stats.duplicate(),
		"p2_combo_stats": _current_bots[1].combo_stats.duplicate(),
		"p1_combo_log": _current_bots[0].combo_log.duplicate(),
	}
	_results.append(result)
	print("[SimResult] game=%d winner=%d turns=%d p1z=%d p2z=%d reason=%s" % [_games_completed + 1, winner_id, gs.turn_number, gs.players[0].monster_zone, gs.players[1].monster_zone, reason])
	_games_completed += 1
	if _games_completed % 10 == 0 or _games_completed == num_games:
		print("[Sim] %d/%d games complete" % [_games_completed, num_games])


func _on_effect_resolving(_player_id: int, card: Dictionary) -> void:
	var id: String = CardUtils.base_id(card)
	_effect_counts[id] = _effect_counts.get(id, 0) + 1


func _print_summary() -> void:
	# First line of the summary: run_sim_diff.sh waits for it, then reads the
	# counts for the cards the diff touches.
	var parts: PackedStringArray = []
	var ids: Array[String] = _effect_counts.keys()
	ids.sort()
	for id in ids:
		parts.append("%s=%d" % [id, _effect_counts[id]])
	print("[SimEffects] %s" % (" ".join(parts) if _effect_counts_available else "unavailable"))
	var p1_wins: int = 0
	var p2_wins: int = 0
	var draws: int = 0
	var total_turns: int = 0
	var p1_combo_detected: int = 0
	var p1_combo_full: int = 0
	var p1_combo_executed: int = 0
	var p2_combo_detected: int = 0
	var p2_combo_full: int = 0
	var p2_combo_executed: int = 0

	for r in _results:
		total_turns += r.turns
		if r.winner == 0:
			p1_wins += 1
		elif r.winner == 1:
			p2_wins += 1
		else:
			draws += 1
		if r.p1_combo_stats.get("detected", 0) > 0:
			p1_combo_detected += 1
		if r.p1_combo_stats.get("full", 0) > 0:
			p1_combo_full += 1
		if r.p1_combo_stats.get("executed", 0) > 0:
			p1_combo_executed += 1
		if r.p2_combo_stats.get("detected", 0) > 0:
			p2_combo_detected += 1
		if r.p2_combo_stats.get("full", 0) > 0:
			p2_combo_full += 1
		if r.p2_combo_stats.get("executed", 0) > 0:
			p2_combo_executed += 1

	var n: int = _results.size()
	var avg_turns: float = float(total_turns) / maxi(n, 1)

	print("")
	print("=== Bot Simulation Results (%d games) ===" % n)
	print("P1 (%s) wins: %d  |  P2 (%s) wins: %d  |  Draws: %d" % [
		BotConfig.Difficulty.keys()[p1_difficulty], p1_wins,
		BotConfig.Difficulty.keys()[p2_difficulty], p2_wins, draws])
	print("Avg turns: %.1f" % avg_turns)
	print("")
	print("P1 Combo Stats:")
	print("  Detected: %d/%d games  |  Full: %d/%d  |  Executed: %d/%d" % [
		p1_combo_detected, n, p1_combo_full, n, p1_combo_executed, n])
	print("P2 Combo Stats:")
	print("  Detected: %d/%d games  |  Full: %d/%d  |  Executed: %d/%d" % [
		p2_combo_detected, n, p2_combo_full, n, p2_combo_executed, n])
	print("")

	# Win reason breakdown
	var reasons: Dictionary = {}
	for r in _results:
		var key: String = "P%d: %s" % [r.winner + 1, r.reason] if r.winner >= 0 else "Draw: %s" % r.reason
		reasons[key] = reasons.get(key, 0) + 1
	print("Win reasons:")
	for key in reasons:
		print("  %s: %d" % [key, reasons[key]])

	# Per-game combo diagnostics
	print("")
	print("=== Per-Game Combo Log (P1) ===")
	for i in range(_results.size()):
		var r: Dictionary = _results[i]
		var winner_str: String = "P1 WIN" if r.winner == 0 else "P2 WIN"
		var cs: Dictionary = r.p1_combo_stats
		var log: Array = r.get("p1_combo_log", [])
		print("Game %d: %s (%s) | T%d z%d r%d | full=%d exec=%d viab=%d" % [
			i + 1, winner_str, r.reason,
			r.turns, r.p1_zone, cs.get("final_rank", 0),
			cs.get("full", 0), cs.get("executed", 0), cs.get("max_viability", 0)])
		for entry in log:
			print("  %s" % entry)
