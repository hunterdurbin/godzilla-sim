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

## Fired once the session is ready for module binding. On host/solo this
## fires at the end of start_host_session(). On client/spectator the host
## scene's RPC handler calls `mark_client_started()` after populating
## client_players for the first time, which fires the same signal —
## modules can subscribe once and bind regardless of mode.
signal session_started

## True once `session_started` has emitted (host or client/spectator path).
var _client_started: bool = false

var turn_manager: TurnManager
var bot_player: BotPlayer
var replay_recorder: ReplayRecorder

# Client-mode cache. Populated by the host scene's RPC handler on each
# state broadcast. On client peers turn_manager / game_state are null —
# `get_player()` falls back to client_players, and modules that want
# modifier data should read these arrays directly. Host peers never use
# these (turn_manager is authoritative).
var client_players: Array[PlayerState] = []
var client_cp_modifiers: Array = [0, 0]
var client_threat_modifiers: Array = [0, 0]
var client_zone_cp_mods: Array = [[], []]
var client_strategy_cp_mods: Array = [[], []]
var client_zone_rank_mods: Array = [[], []]
var client_hand_rank_mods: Array = [[], []]
var client_monster_cp_mods: Array = [0, 0]

# Typed forwarders for the most-frequented members of `turn_manager`.
# Set during start_host_session() so the presentation scene can reach into
# `session.effect_handler` / `session.game_state` / etc. without chaining
# through `turn_manager.action_handler.effect_handler`.
var action_handler: ActionHandler
var effect_handler: EffectHandler
var rules_engine: RulesEngine
var game_state: GameState

var _board: Node


func _ready() -> void:
	_board = get_parent()
	# Cross-scene multiplayer contract: every GameBoard scene's root node
	# must be named "GameBoard" so MultiplayerSync's NodePath is identical
	# on host and client even when they load different .tscn files (mobile
	# vs desktop, etc.). Catching this at startup beats a silent RPC break.
	if _board and _board.name != "GameBoard":
		push_error("[GameSession] Parent node is named '%s' — must be named 'GameBoard' for cross-scene multiplayer to work. See docs/new_game_board.md." % _board.name)
	# Structural assertion: MultiplayerSync must be a named child for the
	# RPC NodePath contract. EffectUIRouter is recommended but not strictly
	# required (scenes without effect prompts can omit it).
	if get_node_or_null("MultiplayerSync") == null:
		push_error("[GameSession] No 'MultiplayerSync' child node — multiplayer RPCs will not route. See docs/new_game_board.md § 'Cross-scene multiplayer contract'.")
	if get_node_or_null("EffectUIRouter") == null:
		push_warning("[GameSession] No 'EffectUIRouter' child node — effect prompts will silently auto-resolve. Add one if your scene plays cards with effects.")


## Snapshot accessors for properties that change as the game progresses.
## These read live state — call after the host session is started.
func current_player_id() -> int:
	return game_state.current_player_id if game_state else -1


func current_phase() -> CardEnums.GamePhase:
	return game_state.current_phase if game_state else CardEnums.GamePhase.START


## Returns the PlayerState for a given player id (0 or 1).
## On host/solo peers reads from turn_manager.game_state. On client peers
## (where turn_manager is null) falls back to the broadcast-state cache
## populated by the host RPC handler. Returns null only if neither source
## has data yet.
func get_player(player_id: int) -> PlayerState:
	if player_id < 0 or player_id > 1:
		return null
	if game_state and player_id < game_state.players.size():
		return game_state.players[player_id]
	if player_id < client_players.size():
		return client_players[player_id]
	return null


## Called by the host scene's RPC state handler after the first state
## broadcast has populated client_players. Emits session_started once
## (idempotent) so modules can bind on either host or client/spectator
## paths via a single signal.
func mark_client_started() -> void:
	if _client_started:
		return
	_client_started = true
	session_started.emit()


## True once the host session has been built and the game is running.
func is_running() -> bool:
	return turn_manager != null


func is_game_over() -> bool:
	return turn_manager != null and turn_manager.is_game_over


# --- Verb forwarders into TurnManager. The presentation scene only needs to
# know about GameSession; these stand in for direct turn_manager calls. ---

func start_game(first_player_id: int) -> void:
	if turn_manager:
		turn_manager.start_game(first_player_id)


func resume_to_main_phase(player_id: int, resolve_effects: bool) -> void:
	if turn_manager:
		turn_manager.resume_to_main_phase(player_id, resolve_effects)


func submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	if turn_manager:
		turn_manager.submit_action(action, params)


func confirm() -> void:
	if turn_manager:
		turn_manager.confirm()


## Forces the game-over flow (used by concede / disconnect claim-win paths).
func end_game(winner_id: int, reason_key: String) -> void:
	if turn_manager:
		turn_manager._on_game_over(winner_id, reason_key)


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

	# Wire forwarders so callers can reach session.effect_handler / game_state /
	# rules_engine / action_handler directly (no chaining through turn_manager).
	action_handler = turn_manager.action_handler
	effect_handler = turn_manager.action_handler.effect_handler
	rules_engine = turn_manager.rules_engine
	game_state = turn_manager.game_state

	session_started.emit()
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
