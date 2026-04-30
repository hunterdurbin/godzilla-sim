class_name GameSession
extends Node

## Owns the runtime layer of a game: TurnManager, BotPlayer, ReplayRecorder.
## Phase 2 is staged across sub-phases:
##   2a (this step) — node exists in the scene tree; behavior unchanged.
##   2b — TurnManager construction moves from game_board._ready() into start().
##   2c — BotPlayer + ReplayRecorder migrate.
##   2d — signal wiring centralizes here, rematch deduplication.
##
## The presentation scene reads `turn_manager` off this node (or via a typed
## accessor added in Phase 4) and connects to its signals.

var turn_manager: TurnManager
var bot_player: BotPlayer
var replay_recorder: ReplayRecorder

var _board: Node


func _ready() -> void:
	_board = get_parent()


## Construct a fresh TurnManager for the host/solo path.
## Creates TurnManager, runs setup() or setup_from_save(), seeds player names.
## Returns the new TurnManager so the caller can wire signals and proceed.
##
## Used by both initial game start and the rematch flow — single source of
## truth for host-side TurnManager construction.
func start_host_session(card_data_node: Node, local_player_id: int, loaded_save: Dictionary = {}) -> TurnManager:
	turn_manager = TurnManager.new()
	if loaded_save.is_empty():
		turn_manager.setup(card_data_node)
	else:
		turn_manager.setup_from_save(loaded_save)

	turn_manager.game_state.player_names[local_player_id] = GameSettings.player_name
	GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)

	return turn_manager


## Construct + wire BotPlayer for Solo v Bot mode. Caller must have already
## set up turn_manager via start_host_session(). Connects bot to all decision
## signals. Sets player_names[1] to "Bot" and re-disambiguates the log.
## Returns the BotPlayer so callers can store a local reference if useful.
func setup_bot(local_player_id: int) -> BotPlayer:
	bot_player = BotPlayer.new()
	bot_player.config = NetworkManager.bot_config
	bot_player.bot_player_id = 1
	bot_player.game_state = turn_manager.game_state
	bot_player.rules_engine = turn_manager.rules_engine
	bot_player.turn_manager = turn_manager
	bot_player.action_handler = turn_manager.action_handler
	bot_player.effect_handler = turn_manager.action_handler.effect_handler
	bot_player.scene_tree = get_tree()

	turn_manager.awaiting_player_action.connect(bot_player._on_awaiting_action)
	turn_manager.confirmation_requested.connect(bot_player._on_confirmation_requested)
	turn_manager.action_handler.monster_rankup_requested.connect(bot_player._on_monster_rankup_requested)
	bot_player.effect_handler.choice_requested.connect(bot_player._on_choice_requested)
	bot_player.effect_handler.hand_discard_requested.connect(bot_player._on_hand_discard_requested)
	bot_player.effect_handler.deck_search_requested.connect(bot_player._on_deck_search_requested)
	bot_player.effect_handler.deck_arrange_requested.connect(bot_player._on_deck_arrange_requested)
	bot_player.effect_handler.card_select_requested.connect(bot_player._on_card_select_requested)
	bot_player.effect_handler.hand_card_selection_requested.connect(bot_player._on_hand_card_selection_requested)
	bot_player.effect_handler.zone_target_requested.connect(bot_player._on_zone_target_requested)
	bot_player.effect_handler.strategy_target_requested.connect(bot_player._on_strategy_target_requested)
	bot_player.effect_handler.cards_revealed_requested.connect(bot_player._on_cards_revealed_requested)

	bot_player.analyze_deck()

	turn_manager.game_state.player_names[1] = "Bot"
	GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)
	return bot_player


## Construct + start ReplayRecorder. Records every game from move 0; saved or
## discarded at game end depending on outcome. Caller must have already set
## up turn_manager via start_host_session(). Returns the recorder.
func setup_replay_recorder(is_bot_game: bool) -> ReplayRecorder:
	replay_recorder = ReplayRecorder.new()
	var seed_val: int = NetworkManager.bot_seed if NetworkManager.bot_seed >= 0 else 0
	var mode_str: String
	match NetworkManager.mode:
		NetworkManager.Mode.SOLO: mode_str = "solo"
		NetworkManager.Mode.SOLO_BOT: mode_str = "solo_bot"
		NetworkManager.Mode.HOST, NetworkManager.Mode.CLIENT: mode_str = "lan"
		NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT: mode_str = "online"
		_: mode_str = "unknown"
	var diff_str: String = BotConfig.Difficulty.keys()[NetworkManager.bot_difficulty] if is_bot_game else ""
	var d_names: Array[String] = [
		DecklistManager.get_player_deck_name(0),
		DecklistManager.get_player_deck_name(1),
	]
	replay_recorder.start(turn_manager.game_state, seed_val, mode_str, diff_str, d_names, get_tree())
	turn_manager.log_message.connect(replay_recorder.on_log_message)
	turn_manager.sub_phase_changed.connect(replay_recorder.on_phase_boundary)
	return replay_recorder
