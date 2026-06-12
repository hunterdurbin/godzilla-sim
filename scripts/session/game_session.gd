class_name GameSession
extends Node

## Owns the runtime layer of a game session: TurnManager, BotPlayer,
## ReplayRecorder, and the client-side state caches populated from host RPC
## broadcasts. The presentation scene (game_board.gd) reads these off the
## session; during extraction it keeps forwarding properties under the old
## names so untouched code continues to work.
##
## Cross-scene multiplayer contract: every GameBoard scene's root node must be
## named "GameBoard" so MultiplayerSync's NodePath is identical on host and
## client even when they load different .tscn files.

## Fired once the session is ready for module binding. On host/solo this fires
## at the end of start_host_session(). On client peers the board's RPC state
## handler calls mark_client_started() after the first broadcast populates
## client_players — modules can subscribe once and bind regardless of mode.
signal session_started

## Fired by MultiplayerSync after every applied state broadcast (client
## peers only). Client-side PlayerState objects are rebuilt per receive,
## so bound HUD components rebind + refresh on this signal.
signal client_state_applied

var turn_manager: TurnManager # Only exists on host/solo
var bot_player: BotPlayer
var replay_recorder: ReplayRecorder

# Typed forwarders for the most-frequented members of `turn_manager`.
# Set during start_host_session(). Null on client peers.
var action_handler: ActionHandler
var effect_handler: EffectHandler
var rules_engine: RulesEngine
var game_state: GameState
var player_input: SignalPlayerInput
var events: GameEvents

# Client-mode cache. Populated by the board's RPC state handler on each
# broadcast. On client peers turn_manager is null — get_player() falls back
# to client_players. Host peers never use these (turn_manager is
# authoritative).
var client_players: Array[PlayerState] = []
var client_current_player_id: int = 0
var client_turn_number: int = 0
var client_phase: CardEnums.GamePhase = CardEnums.GamePhase.START
var client_playable: Dictionary = {} # Playable card/zone indices from host
var client_cp_modifiers: Array = [0, 0]
var client_threat_modifiers: Array = [0, 0]
var client_zone_cp_mods: Array = [[], []]
var client_strategy_cp_mods: Array = [[], []]
var client_zone_rank_mods: Array = [[], []]
var client_hand_rank_mods: Array = [[], []]
var client_monster_cp_mods: Array = [0, 0]
var client_gradients_applied: bool = false
# Client-side stats snapshot (synced from host for disconnect reporting)
var client_stats_elapsed_ms: Array[int] = [0, 0]
var client_stats_game_start_ms: int = 0
var client_stats_turn_start_ms: int = 0
var client_stats_opponent_hand: Array = []
var client_stats_deck_names: Array[String] = ["", ""]
var client_stats_decklists: Array = [null, null]

var _client_started: bool = false
var _board: Node


func _ready() -> void:
	_board = get_parent()
	if _board and _board.name != "GameBoard":
		push_error("[GameSession] Parent node is named '%s' — must be named 'GameBoard' for cross-scene multiplayer to work." % _board.name)
	if get_node_or_null("MultiplayerSync") == null:
		push_error("[GameSession] No 'MultiplayerSync' child node — multiplayer RPCs will not route.")


## Returns the PlayerState for a given player id (0 or 1).
## On host/solo peers reads from turn_manager's game state. On client peers
## (where turn_manager is null) falls back to the broadcast-state cache.
func get_player(player_id: int) -> PlayerState:
	if player_id < 0 or player_id > 1:
		return null
	if game_state and player_id < game_state.players.size():
		return game_state.players[player_id]
	if player_id < client_players.size():
		return client_players[player_id]
	return null


## Called by the board's RPC state handler after the first state broadcast
## has populated client_players. Emits session_started once (idempotent).
func mark_client_started() -> void:
	if _client_started:
		return
	_client_started = true
	session_started.emit()


## True once the host session has been built and the game is running.
func is_running() -> bool:
	return turn_manager != null


## Compute the net play-cost modifier for each card in the given player's hand.
## Returned array is parallel to player.hand. Returns [] if no effect handler.
## Used by the board's hand display (host side) and the state broadcast.
func compute_hand_rank_mods(player: PlayerState) -> Array:
	var out: Array = []
	if not turn_manager:
		return out
	var eh: EffectHandler = turn_manager.effect_handler
	if not eh:
		return out
	for card in player.hand:
		var mod: int = eh.get_play_rank_modifier(player.player_id, card)
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			mod += eh.get_strategy_hand_rank_modifier(player.player_id, card)
		out.append(mod)
	return out


## Construct a fresh TurnManager for the host/solo path: runs setup() or
## setup_from_save(), seeds the local player name, wires the typed
## forwarders, and emits session_started. Single source of truth for
## host-side TurnManager construction (initial start and rematch).
func start_host_session(card_data_node: Node, local_player_id: int, loaded_save: Dictionary = {}, config: SessionConfig = null) -> TurnManager:
	var cfg := config if config else SessionConfig.from_singletons()
	turn_manager = TurnManager.new()
	if loaded_save.is_empty():
		turn_manager.setup(card_data_node, cfg)
	else:
		turn_manager.setup_from_save(loaded_save)
		turn_manager.session_config = cfg

	if local_player_id >= 0 and not cfg.local_player_name.is_empty():
		turn_manager.game_state.player_names[local_player_id] = cfg.local_player_name
	if local_player_id >= 0:
		# GameLog is display-only and process-global; a dedicated server
		# (local_player_id -1) must not touch it — clients disambiguate names
		# themselves when applying state broadcasts.
		GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)

	action_handler = turn_manager.action_handler
	effect_handler = turn_manager.action_handler.effect_handler
	rules_engine = turn_manager.rules_engine
	game_state = turn_manager.game_state
	player_input = turn_manager.player_input
	events = turn_manager.events

	session_started.emit()
	return turn_manager


## Construct + wire BotPlayer for Solo v Bot mode. Caller must have already
## run start_host_session(). Connects the bot to all decision signals, sets
## player_names[1] to "Bot", and re-disambiguates the log.
func setup_bot(local_player_id: int) -> BotPlayer:
	bot_player = BotPlayer.new()
	bot_player.config = NetworkManager.bot_config
	bot_player.bot_player_id = 1
	bot_player.game_state = turn_manager.game_state
	bot_player.rules_engine = turn_manager.rules_engine
	bot_player.turn_manager = turn_manager
	bot_player.action_handler = turn_manager.action_handler
	bot_player.effect_handler = turn_manager.action_handler.effect_handler
	bot_player.player_input = turn_manager.player_input
	bot_player.scene_tree = get_tree()

	turn_manager.awaiting_player_action.connect(bot_player._on_awaiting_action)
	var pin: SignalPlayerInput = turn_manager.player_input
	pin.confirmation_requested.connect(bot_player._on_confirmation_requested)
	pin.monster_rankup_requested.connect(bot_player._on_monster_rankup_requested)
	pin.choice_requested.connect(bot_player._on_choice_requested)
	pin.hand_discard_requested.connect(bot_player._on_hand_discard_requested)
	pin.deck_search_requested.connect(bot_player._on_deck_search_requested)
	pin.deck_arrange_requested.connect(bot_player._on_deck_arrange_requested)
	pin.card_select_requested.connect(bot_player._on_card_select_requested)
	pin.hand_card_selection_requested.connect(bot_player._on_hand_card_selection_requested)
	pin.zone_target_requested.connect(bot_player._on_zone_target_requested)
	pin.strategy_target_requested.connect(bot_player._on_strategy_target_requested)
	pin.cards_revealed_requested.connect(bot_player._on_cards_revealed_requested)

	bot_player.analyze_deck()

	turn_manager.game_state.player_names[1] = "Bot"
	GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)
	return bot_player


## Construct + start ReplayRecorder. Caller must have already run
## start_host_session().
func setup_replay_recorder(is_bot_game: bool) -> ReplayRecorder:
	replay_recorder = ReplayRecorder.new()
	var seed_val: int = NetworkManager.bot_seed if NetworkManager.bot_seed >= 0 else 0
	var mode_str: String
	match NetworkManager.mode:
		NetworkManager.Mode.SOLO: mode_str = "solo"
		NetworkManager.Mode.SOLO_BOT: mode_str = "solo_bot"
		NetworkManager.Mode.HOST, NetworkManager.Mode.CLIENT: mode_str = "lan"
		NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT, NetworkManager.Mode.ONLINE: mode_str = "online"
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
