extends Node

## Runs N bot-vs-bot games headlessly and prints summary statistics.
## Usage: godot --headless --path . scenes/simulation/BotSimulationRunner.tscn

@export var num_games: int = 100
@export var p1_difficulty: BotConfig.Difficulty = BotConfig.Difficulty.HARD
@export var p2_difficulty: BotConfig.Difficulty = BotConfig.Difficulty.NORMAL
@export var p1_deck_name: String = "shin (Ian)"
@export var p2_deck_name: String = "ESD02 Starter"
@export var base_seed: int = 0

var _games_completed: int = 0
var _results: Array[Dictionary] = []
var _current_turn_manager: TurnManager
var _current_bots: Array = [] # [BotPlayer, BotPlayer]
var _game_running: bool = false


func _ready() -> void:
	# Uncap frame rate for maximum simulation speed
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 10000
	if base_seed == 0:
		base_seed = randi()
	print("=== Bot Simulation Starting (%d games, seed=%d) ===" % [num_games, base_seed])
	print("P1: %s  |  P2: %s" % [
		BotConfig.Difficulty.keys()[p1_difficulty],
		BotConfig.Difficulty.keys()[p2_difficulty]])
	_start_next_game()


func _start_next_game() -> void:
	if _games_completed >= num_games:
		_print_summary()
		get_tree().quit()
		return

	seed(base_seed + _games_completed)

	# Set up decks via DecklistManager
	for i in range(2):
		var deck_name: String = p1_deck_name if i == 0 else p2_deck_name
		if not deck_name.is_empty():
			DecklistManager.select_deck_for_player(i, deck_name)
		elif not DecklistManager.has_player_deck(i):
			# No deck selected — clear so setup() uses fallback
			pass

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
	bot1.scene_tree = get_tree()  # Needed for async signal timing

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

	# Instant confirmation — resolve synchronously (no await, no frame wait).
	# Must be connected BEFORE bot handlers so it fires first.
	var tm := _current_turn_manager
	tm.confirmation_requested.connect(func(_p: String, _s: String) -> void: tm.confirm())

	# Connect signals for both bots (same pattern as game_board._setup_bot)
	for bot in _current_bots:
		_current_turn_manager.awaiting_player_action.connect(bot._on_awaiting_action)
		_current_turn_manager.action_handler.monster_rankup_requested.connect(bot._on_monster_rankup_requested)
		bot.effect_handler.choice_requested.connect(bot._on_choice_requested)
		bot.effect_handler.hand_discard_requested.connect(bot._on_hand_discard_requested)
		bot.effect_handler.deck_search_requested.connect(bot._on_deck_search_requested)
		bot.effect_handler.deck_arrange_requested.connect(bot._on_deck_arrange_requested)
		bot.effect_handler.card_select_requested.connect(bot._on_card_select_requested)
		bot.effect_handler.hand_card_selection_requested.connect(bot._on_hand_card_selection_requested)
		bot.effect_handler.zone_target_requested.connect(bot._on_zone_target_requested)
		bot.effect_handler.strategy_target_requested.connect(bot._on_strategy_target_requested)
		bot.effect_handler.cards_revealed_requested.connect(bot._on_cards_revealed_requested)

	# Analyze decks / init combos
	bot1.analyze_deck()
	bot2.analyze_deck()

	# Connect game_ended to record result
	_current_turn_manager.game_ended.connect(_on_game_ended)

	# Safety: cap at 50 turns to avoid infinite loops
	_current_turn_manager.turn_started.connect(_on_turn_started)

	_game_running = true
	_current_turn_manager.start_game(_games_completed % 2)  # Alternate starting player


func _on_turn_started(_player_id: int) -> void:
	if _current_turn_manager.game_state.turn_number > 50:
		print("[Sim] Game %d exceeded 50 turns — forcing draw" % (_games_completed + 1))
		_record_result(-1, "Turn limit exceeded")
		_current_turn_manager.is_game_over = true
		_game_running = false
		_start_next_game.call_deferred()


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
	_games_completed += 1
	if _games_completed % 10 == 0 or _games_completed == num_games:
		print("[Sim] %d/%d games complete" % [_games_completed, num_games])


func _print_summary() -> void:
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
