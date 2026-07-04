extends Control

## Main game controller. Orchestrates the UI, TurnManager, and both PlayerBoards.
## In multiplayer, the host runs TurnManager and broadcasts state to the client.
## The client receives state via RPC and sends actions back to the host.

## Forwarding property into GameSession (session owns it; only exists on
## host/solo). Kept under the old name during extraction so existing code
## keeps working — reads/writes go through _session.
var turn_manager: TurnManager:
	get: return _session.turn_manager
	set(v): _session.turn_manager = v
const CardScript := preload("res://scenes/cards/card.gd")
var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# Replay recording (owned by GameSession; forwarding property)
var replay_recorder: ReplayRecorder:
	get: return _session.replay_recorder
	set(v): _session.replay_recorder = v
var _save_game_button: Button
var _loaded_from_save: bool = false

# Bot state (bot_player owned by GameSession; forwarding property)
var bot_player: BotPlayer:
	get: return _session.bot_player
	set(v): _session.bot_player = v
var is_bot_game: bool = false
var _bot_seed_was_explicit: bool = false
var _bot_cards_visible: bool = false
var _bot_visibility_button: Button

# Lobby-bot state (Play vs Bot While You Wait)
var _is_lobby_bot: bool = false
var _lobby_banner: Control = null
var _lobby_banner_label: Label = null
var _lobby_banner_start_msec: int = 0

# In-flight action feedback (multiplayer client only)
var _pending_indicator: Panel = null
var _pending_indicator_label: Label = null
var _action_submitted_ms: int = 0
const PENDING_INDICATOR_STALL_MS: int = 3000  ## silence after a submit before we call the server unresponsive
var _opponent_found_dialog: AcceptDialog = null
var _opponent_found_timer: Timer = null
var _opponent_found_remaining: int = 0
var _opponent_found_handled: bool = false

# Multiplayer state
var is_multiplayer_game: bool = false
var local_player_id: int = 0 # 0 for host/solo, 1 for client

# Client-side state (populated from host RPCs). Owned by GameSession;
# forwarding properties under the old names during extraction.
var _client_players: Array[PlayerState]:
	get: return _session.client_players
	set(v): _session.client_players = v
var _client_current_player_id: int:
	get: return _session.client_current_player_id
	set(v): _session.client_current_player_id = v
var _client_turn_number: int:
	get: return _session.client_turn_number
	set(v): _session.client_turn_number = v
var _client_phase: CardEnums.GamePhase:
	get: return _session.client_phase
	set(v): _session.client_phase = v
var _client_playable: Dictionary: # Playable card/zone indices from host
	get: return _session.client_playable
	set(v): _session.client_playable = v
var _client_cp_modifiers: Array:
	get: return _session.client_cp_modifiers
	set(v): _session.client_cp_modifiers = v
var _client_threat_modifiers: Array:
	get: return _session.client_threat_modifiers
	set(v): _session.client_threat_modifiers = v
var _client_zone_cp_mods: Array:
	get: return _session.client_zone_cp_mods
	set(v): _session.client_zone_cp_mods = v
var _client_strategy_cp_mods: Array:
	get: return _session.client_strategy_cp_mods
	set(v): _session.client_strategy_cp_mods = v
var _client_zone_rank_mods: Array:
	get: return _session.client_zone_rank_mods
	set(v): _session.client_zone_rank_mods = v
var _client_hand_rank_mods: Array:
	get: return _session.client_hand_rank_mods
	set(v): _session.client_hand_rank_mods = v
var _client_monster_cp_mods: Array:
	get: return _session.client_monster_cp_mods
	set(v): _session.client_monster_cp_mods = v
var _client_modifier_breakdowns: Dictionary:
	get: return _session.client_modifier_breakdowns
	set(v): _session.client_modifier_breakdowns = v
var _client_gradients_applied: bool:
	get: return _session.client_gradients_applied
	set(v): _session.client_gradients_applied = v
# Client-side stats snapshot (synced from host for disconnect reporting)
var _client_stats_elapsed_ms: Array[int]:
	get: return _session.client_stats_elapsed_ms
	set(v): _session.client_stats_elapsed_ms = v
var _client_stats_game_start_ms: int:
	get: return _session.client_stats_game_start_ms
	set(v): _session.client_stats_game_start_ms = v
var _client_stats_turn_start_ms: int:
	get: return _session.client_stats_turn_start_ms
	set(v): _session.client_stats_turn_start_ms = v
var _client_stats_opponent_hand: Array:
	get: return _session.client_stats_opponent_hand
	set(v): _session.client_stats_opponent_hand = v
var _client_stats_deck_names: Array[String]:
	get: return _session.client_stats_deck_names
	set(v): _session.client_stats_deck_names = v
var _client_stats_decklists: Array:
	get: return _session.client_stats_decklists
	set(v): _session.client_stats_decklists = v

# Session layer. _sync owns the @rpc contract at a stable NodePath
# (GameBoard/GameSession/MultiplayerSync) so RPCs route identically on host
# and client; its methods forward back here while extraction is in progress.
@onready var _session: GameSession = $GameSession
@onready var _sync: MultiplayerSync = $GameSession/MultiplayerSync
@onready var _board_sfx: BoardSfx = $BoardSfx
@onready var _log_chat: LogChat = $LogChat
@onready var _tracker: TurnTrackerModule = $TurnTrackerModule
@onready var _first_player: FirstPlayerUI = $FirstPlayerUI
@onready var _end_game: EndGameController = $EndGameController
@onready var _reconnect: ReconnectController = $ReconnectController
@onready var _router: EffectUIRouter = $GameSession/EffectUIRouter
@onready var _ability_banner: ActiveAbilityBanner = $ActiveAbilityBanner
@onready var _hand: HandController = $HandController
@onready var _selection: SelectionController = $SelectionController
@onready var _mobile: MobileLayout = $MobileLayout
@onready var _effect_stack: EffectStackPanel = $EffectStackPanel

# UI references
@onready var player1_board: Control = $VBoxContainer/BoardArea/BoardColumn/Player1Board
@onready var player2_board: Control = $VBoxContainer/BoardArea/BoardColumn/Player2Board
@onready var action_panel: Control = $ActionPanel
@onready var log_output: RichTextLabel = $LogPanel/LogVBox/LogOutput
@onready var chat_input: LineEdit = $LogPanel/LogVBox/ChatRow/ChatInput
@onready var chat_char_count: Label = $LogPanel/LogVBox/ChatRow/CharCount
## Log entries — owned by LogChat (forwarding properties during extraction)
var _log_tokens: Array:
	get: return _log_chat.log_tokens
	set(v): _log_chat.log_tokens = v
var _pending_log_tokens: Array:
	get: return _log_chat.pending_log_tokens
	set(v): _log_chat.pending_log_tokens = v
# Sound events buffered for client — owned by BoardSfx (forwarding property;
# MultiplayerSync drains it at broadcast time)
var _pending_sound_events: PackedStringArray:
	get: return _board_sfx._pending_sound_events
	set(v): _board_sfx._pending_sound_events = v
@onready var end_game_panel: Control = $EndGamePanel
@onready var btn_rematch: Button = $EndGamePanel/VBox/ButtonRow/RematchButton
@onready var btn_end_menu: Button = $EndGamePanel/VBox/ButtonRow/MenuButton
@onready var action_prompt_panel: PanelContainer = $ActionPrompt
@onready var card_select_prompt: Label = $ActionPrompt/PromptLabel
@onready var btn_bug_report: Button = $BugReportButton
@onready var btn_concede: Button = $ConcedeButton
@onready var btn_main_menu: Button = $MainMenuButton
@onready var btn_sound_toggle: Button = $SoundToggleButton
@onready var btn_music_toggle: Button = $MusicToggleButton

# Hand references
@onready var player1_hand: Node2D = $Player1Hand
@onready var player2_hand: Node2D = $Player2Hand
@onready var player1_hand_space: Control = $VBoxContainer/BoardArea/BoardColumn/Player1HandSpace
@onready var player2_hand_space: Control = $VBoxContainer/BoardArea/BoardColumn/Player2HandSpace

# Action buttons
@onready var btn_play_battle: Button = $ActionPanel/Row1/PlayBattle
@onready var btn_play_strategy: Button = $ActionPanel/Row1/PlayStrategy
@onready var btn_gain_rage: Button = $ActionPanel/Row1/GainRage
@onready var btn_play_monster: Button = $ActionPanel/Row2/PlayMonster
@onready var btn_invade: Button = $ActionPanel/Row2/Invade
@onready var btn_end_main: Button = $ActionPanel/Row2/EndMain
@onready var btn_cancel: Button = $ActionPanel/Row0/Cancel
@onready var btn_confirm: Button = $ActionPanel/Row0/Confirm

# Deck search UI references
@onready var deck_search_overlay: DeckSearchOverlayUI = $DeckSearchOverlay
# Internal deck-search widget refs kept ONLY for the mobile styling pass
# (logic lives in deck_search_overlay.gd now)
@onready var deck_search_skip: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/SkipButton
@onready var deck_search_show_all: CheckButton = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/ShowAllToggle
@onready var deck_search_stacked: CheckButton = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/StackedToggle
@onready var deck_search_view_board: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/ViewBoardButton
@onready var hand_toggle_button: Button = $HandButtonStack/HandToggleButton
@onready var sort_hand_button: Button = $HandButtonStack/SortHandButton
@onready var opponent_hand_button_stack: HBoxContainer = $OpponentHandButtonStack
@onready var opponent_hand_toggle_button: Button = $OpponentHandButtonStack/OpponentHandToggleButton
@onready var opponent_sort_hand_button: Button = $OpponentHandButtonStack/OpponentSortHandButton

# Deck arrange overlay UI references
@onready var deck_arrange_overlay: DeckArrangeOverlayUI = $DeckArrangeOverlay
# Internal refs kept ONLY for the mobile styling pass
@onready var deck_arrange_view_board: Button = $DeckArrangeOverlay/DeckArrangePanel/VBox/ButtonRow/ViewBoardButton
@onready var deck_arrange_confirm: Button = $DeckArrangeOverlay/DeckArrangePanel/VBox/ButtonRow/ConfirmButton

# Card select overlay UI references
@onready var card_pool_select_overlay: CardSelectOverlayUI = $CardSelectOverlay
# Internal refs kept ONLY for the mobile styling pass
@onready var card_pool_select_show_all: CheckButton = $CardSelectOverlay/CardSelectPanel/VBox/ToggleRow/ShowAllToggle
@onready var card_pool_select_stacked: CheckButton = $CardSelectOverlay/CardSelectPanel/VBox/ToggleRow/StackedToggle
@onready var card_pool_select_view_board: Button = $CardSelectOverlay/CardSelectPanel/VBox/ToggleRow/ViewBoardButton
@onready var card_pool_select_skip: Button = $CardSelectOverlay/CardSelectPanel/VBox/ButtonRow/SkipButton
@onready var card_pool_select_confirm: Button = $CardSelectOverlay/CardSelectPanel/VBox/ButtonRow/ConfirmButton

# Discard view UI references
@onready var discard_view_overlay: CardGridViewerUI = $DiscardViewOverlay
# Internal refs kept ONLY for the mobile styling pass
@onready var discard_view_close: Button = $DiscardViewOverlay/DiscardViewPanel/VBox/CloseButton
@onready var discard_view_stacked: CheckButton = $DiscardViewOverlay/DiscardViewPanel/VBox/StackedToggle

# In-game stacked preference (initialized from GameSettings, remembered for the match)
var _match_stacked_view: bool:
	get: return _router.match_stacked_view
	set(v): _router.match_stacked_view = v


var _view_board_source_overlay: Control = null
var _minimize_chip: MinimizeChip = null

# Monster deck view UI references
@onready var monster_deck_view_overlay: CardGridViewerUI = $MonsterDeckViewOverlay
# Internal refs kept ONLY for the mobile styling pass
@onready var monster_deck_view_close: Button = $MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/CloseButton
@onready var monster_deck_view_stacked: CheckButton = $MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/StackedToggle

# Zone stack view UI references
@onready var zone_stack_view_overlay: CardGridViewerUI = $ZoneStackViewOverlay
# Internal ref kept ONLY for the mobile styling pass
@onready var zone_stack_view_close: Button = $ZoneStackViewOverlay/ZoneStackViewPanel/VBox/CloseButton

# Card zoom overlay
@onready var card_zoom_overlay: CardZoomOverlayUI = $CardZoomOverlay


# Turn tracker: main phase labels [player_id][phase_index]
# Turn tracker labels — owned by TurnTrackerModule (forwarding property for
# the header name updates that remain on the board during extraction)
var _turn_tracker_headers: Array:
	get: return _tracker.headers

# Card hover preview
var _preview_container: Control
var _preview_bg: Panel
var _preview_card: Control


# Tracks the Card node that received the most recent effect-card highlight so
# unhighlight can clear it by reference even if its card_data later mutates
# (e.g. evolution stacks a new card via set_card_data_dict on the same node).
var _highlighted_effect_card_node: Control = null

# Tracks the pulsing attention highlight (hovered effect-prompt / stack row).
# Separate from _highlighted_effect_card_node so the two visuals never stomp
# each other's reset.
var _attention_card_node: Control = null
var _attention_discard_pid: int = -1

# State tracking
# Selection state — owned by SelectionController (forwarding properties for
# the board _input path, mobile cluster, sync, and rematch reset)
var pending_action: CardEnums.ActionType:
	get: return _selection.pending_action
	set(v): _selection.pending_action = v
var waiting_for_card_select: bool:
	get: return _selection.waiting_for_card_select
	set(v): _selection.waiting_for_card_select = v
var waiting_for_zone_select: bool:
	get: return _selection.waiting_for_zone_select
	set(v): _selection.waiting_for_zone_select = v
var selected_card_id: String:
	get: return _selection.selected_card_id
	set(v): _selection.selected_card_id = v
var _selected_card_data: Dictionary:
	get: return _selection._selected_card_data
	set(v): _selection._selected_card_data = v
var _awaiting_confirmation: bool = false
var _discard_selecting: bool:
	get: return _selection._discard_selecting
var _discard_player_id: int:
	get: return _selection._discard_player_id
var _hand_card_selecting: bool:
	get: return _selection._hand_card_selecting
var _hand_card_allow_skip: bool:
	get: return _selection._hand_card_allow_skip
var _zone_target_selecting: bool:
	get: return _selection._zone_target_selecting
var _zone_target_allow_skip: bool:
	get: return _selection._zone_target_allow_skip
var _strategy_target_selecting: bool:
	get: return _selection._strategy_target_selecting
var _choice_selecting: bool:
	get: return _selection._choice_selecting
var _zone_select_valid: Array[int]:
	get: return _selection._zone_select_valid
	set(v): _selection._zone_select_valid = v
var _drag_card: Control:
	get: return _selection._drag_card
	set(v): _selection._drag_card = v
var _drag_valid_zones: Array[int]:
	get: return _selection._drag_valid_zones
var _drag_action: CardEnums.ActionType:
	get: return _selection._drag_action
	set(v): _selection._drag_action = v
var _drag_can_rage: bool:
	get: return _selection._drag_can_rage
	set(v): _selection._drag_can_rage = v
var _drag_can_invade: bool:
	get: return _selection._drag_can_invade
	set(v): _selection._drag_can_invade = v
var _confirming_pass: bool:
	get: return _selection._confirming_pass
	set(v): _selection._confirming_pass = v
var _leave_dialog: ConfirmationDialog = null


# Action blocking — prevents input while an action is being processed
var _action_pending: bool = false


# First-player choice state
var _first_player_id: int = 0 # Which player went first (for * indicator)

# Rematch state — owned by EndGameController (forwarding properties for the
# board-side rematch reset and the reconnect cluster during extraction)
var _rematch_requested: bool:
	get: return _end_game.rematch_requested
	set(v): _end_game.rematch_requested = v
var _opponent_rematch_requested: bool:
	get: return _end_game.opponent_rematch_requested
	set(v): _end_game.opponent_rematch_requested = v
var _game_ended_by_disconnect: bool = false
var _rematch_deck_select: VBoxContainer:
	get: return _end_game.rematch_deck_select
	set(v): _end_game.rematch_deck_select = v
var _rematch_deck_changed: bool:
	get: return _end_game.rematch_deck_changed
	set(v): _end_game.rematch_deck_changed = v
var _rematch_deck_name: String:
	get: return _end_game.rematch_deck_name
	set(v): _end_game.rematch_deck_name = v

# Reconnect state — owned by ReconnectController (forwarding properties for
# the main-menu exit, rematch reset, and EndGameController during extraction)
var _reconnect_cumulative_seconds: float:
	get: return _reconnect.cumulative_seconds
	set(v): _reconnect.cumulative_seconds = v
var _waiting_for_reconnect: bool:
	get: return _reconnect.waiting_for_reconnect
	set(v): _reconnect.waiting_for_reconnect = v
var _reconnect_attempting: bool:
	get: return _reconnect.attempting
	set(v): _reconnect.attempting = v
## In-flight host->client prompt, owned by MultiplayerSync (forwarding
## property — overlay request senders still write it during extraction).
var _pending_interaction: Dictionary:
	get: return _sync._pending_interaction
	set(v): _sync._pending_interaction = v
# Reconnect overlay — owned by ReconnectController
var _reconnect_overlay: ColorRect:
	get: return _reconnect.overlay

# Stats time tracking
var _player_elapsed_ms: Array[int] = [0, 0]
var _turn_start_time_ms: int = 0
var _game_start_time_ms: int = 0
var _stats_uploaded: bool:
	get: return _end_game.stats_uploaded
	set(v): _end_game.stats_uploaded = v

# Standby choice selection state (for choosing ability resolution order)

# Monster rank-up selection state


# Turn tracker sub-phase index
# Owned by TurnTrackerModule (forwarding property — MultiplayerSync reads it
# while serializing, several board paths still write it)
var _current_sub_phase: int:
	get: return _tracker.current_sub_phase
	set(v): _tracker.current_sub_phase = v

# Turn tracker transition queue (delays between phase changes)

# Hand expand toggle
# Hand expand state — owned by HandController (forwarding properties for
# _position_hands and the rematch reset during extraction)
var _hand_expanded: bool:
	get: return _hand.hand_expanded
	set(v): _hand.hand_expanded = v
const HAND_EXPAND_OFFSET: float = 160.0

var _opponent_hand_expanded: bool:
	get: return _hand.opponent_hand_expanded
	set(v): _hand.opponent_hand_expanded = v
const OPPONENT_HAND_EXPAND_OFFSET: float = 195.0

# Mobile layout — owned by MobileLayout (forwarding properties for the
# paths that still read mobile state during extraction)
# (null-guarded: _notification can fire before @onready assigns _mobile)
var _is_mobile_layout: bool:
	get: return _mobile != null and _mobile.is_mobile_layout
	set(v): _mobile.is_mobile_layout = v
var _mobile_phase_label: Label:
	get: return _mobile._mobile_phase_label if _mobile else null
var _mobile_chat_bar: PanelContainer:
	get: return _mobile._mobile_chat_bar if _mobile else null
var _fab_main_btn: Button:
	get: return _mobile._fab_main_btn if _mobile else null
var _fab_container: Control:
	get: return _mobile._fab_container if _mobile else null
var _fab_action_btns: Array[Button]:
	get: return _mobile._fab_action_btns if _mobile else []


func _set_action_buttons_visible(vis: bool) -> void:
	action_panel.get_node("Row0").visible = vis
	action_panel.get_node("Row1").visible = vis
	action_panel.get_node("Row2").visible = vis
	if _fab_main_btn:
		_fab_main_btn.visible = vis
		btn_end_main.visible = vis
		btn_confirm.visible = vis
		btn_cancel.visible = vis
		btn_confirm.disabled = true
		btn_cancel.disabled = true
		if not vis:
			_collapse_fab_instant()


func _ready() -> void:
	# Free deck-builder texture cache to reclaim memory for gameplay
	CardScript.clear_texture_cache()

	is_multiplayer_game = NetworkManager.is_multiplayer()
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	_is_lobby_bot = NetworkManager.is_lobby_bot_game()
	local_player_id = NetworkManager.get_local_player_id() if is_multiplayer_game else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)

	# Wire hand CardManagers to PlayerBoards
	player1_board.hand_manager = player1_hand
	player2_board.hand_manager = player2_hand

	# Rearrange layout for client so local player sees their board at bottom
	_arrange_for_local_player()

	# Make turn tracker labels clickable to toggle auto settings
	_tracker.setup_settings_toggles()

	# Effect prompt router: hooks + per-prompt handlers must be registered
	# BEFORE the session starts so the router binds them on session_started.
	_router.translate_prompt = _resolve_translated_text
	_router.on_pre_remote_dispatch = _flush_broadcast
	_router.on_pending_interaction = func(method: String, args: Array, player_id: int) -> void:
		_pending_interaction = {"method": method, "args": args, "player": player_id}
	_router.on_view_board_request = _on_overlay_view_board
	_router.card_zoom_request = _show_card_zoom
	_router.ability_banner_show = _ability_banner.show_ability
	_router.ability_banner_hide = _ability_banner.hide_banner
	card_zoom_overlay.on_hidden = _on_card_zoom_hidden
	_router.register_handler("deck_search", deck_search_overlay.show_prompt)
	_router.register_handler("deck_arrange", deck_arrange_overlay.show_prompt)
	_router.register_handler("card_select", card_pool_select_overlay.show_prompt)
	_router.register_handler("monster_rankup", _show_monster_rankup)
	_router.register_handler("cards_revealed", zone_stack_view_overlay.show_revealed)

	if not is_multiplayer_game or NetworkManager.is_host():
		# Seed RNG: use saved seed if loading, otherwise bot_seed for bot games
		var loaded_seed: int = int(GameSerializer.pending_load.get("game_seed", -1))
		if loaded_seed > 0:
			NetworkManager.bot_seed = loaded_seed
			print("[GameBoard._ready] Using saved game_seed=%d" % loaded_seed)
		if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
			_apply_bot_seed()
		elif loaded_seed > 0:
			# Non-bot mode but has a saved seed — apply it for consistency
			seed(loaded_seed)
			print("[GameBoard._ready] Seeded RNG with %d (non-bot mode)" % loaded_seed)

		# Host / solo: create and run TurnManager (construction owned by session)
		var pending_load: Dictionary = GameSerializer.pending_load
		if not pending_load.is_empty():
			_loaded_from_save = true
			_first_player_id = pending_load.get("first_player_id", 0)
			GameSerializer.pending_load = {}
		_session.start_host_session(CardData, local_player_id, pending_load)
		for i in range(2):
			if i < _turn_tracker_headers.size():
				_turn_tracker_headers[i].text = GameLog.player_name(i)

		# Connect turn manager signals
		turn_manager.phase_started.connect(_on_phase_started)
		turn_manager.phase_ended.connect(_on_phase_ended)
		turn_manager.sub_phase_changed.connect(_on_sub_phase_changed)
		turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		turn_manager.turn_started.connect(_on_turn_started)
		turn_manager.player_input.confirmation_requested.connect(_on_confirmation_requested)

		# Connect action handler signals for visual feedback
		turn_manager.events.battle_card_played.connect(_on_battle_card_played)
		turn_manager.events.monster_advanced.connect(_on_monster_advanced)
		turn_manager.events.battle_card_crushed.connect(_on_battle_card_crushed)
		turn_manager.events.counter_succeeded.connect(_on_counter_succeeded)
		turn_manager.events.play_cancelled.connect(_on_play_cancelled)
		turn_manager.events.counter_failed.connect(_on_counter_failed)
		turn_manager.events.counter_immunity_triggered.connect(_on_counter_immunity_triggered)
		turn_manager.events.counter_prevented.connect(_on_counter_prevented)
		turn_manager.events.monster_countered.connect(_on_monster_countered)

		# Connect effect handler signals for player choice UIs
		turn_manager.action_handler.effect_handler.effect_zone_highlighted.connect(_on_effect_zone_highlighted)
		turn_manager.action_handler.effect_handler.effect_zone_unhighlighted.connect(_on_effect_zone_unhighlighted)
		turn_manager.action_handler.effect_handler.effect_card_highlighted.connect(_on_effect_card_highlighted)
		turn_manager.action_handler.effect_handler.effect_card_unhighlighted.connect(_on_effect_card_unhighlighted)

		# Set up replay recorder
		_setup_replay_recorder()

		# Set up bot player for Solo v Bot mode
		if is_bot_game:
			_setup_bot()

		# Connect player state signals so mid-effect changes (e.g. search_deck adding
		# a card to hand) trigger visual updates immediately
		for player in turn_manager.game_state.players:
			player.hand_changed.connect(_on_state_changed)
			player.zones_changed.connect(_on_state_changed)
			player.rage_changed.connect(_on_state_changed.unbind(1))
			player.monster_changed.connect(_on_state_changed)
			player.discard_changed.connect(_on_state_changed)
			player.deck_changed.connect(_on_state_changed)
			player.strategy_zones_changed.connect(_on_state_changed)
			player.discard_reshuffled.connect(_on_discard_reshuffled.bind(player.player_id))
	else:
		# Client: initialize empty client state, wait for host RPCs
		_client_players = [PlayerState.new(0), PlayerState.new(1)]
		GameLog.player_names[local_player_id] = GameSettings.player_name
		# If this is a reconnect (is_in_game was set before scene load), the host
		# already sent state before this scene existed — request a fresh broadcast.
		if NetworkManager.is_in_game:
			_sync._rpc_request_resync.rpc_id(NetworkManager.host_peer_id)
			RpcLogger.log_send("send_player_name", GameSettings.player_name.length())
			_sync._rpc_send_player_name.rpc_id(NetworkManager.host_peer_id, GameSettings.player_name)

	# Connect buttons
	_selection.setup()
	btn_bug_report.pressed.connect(_on_bug_report_pressed)
	btn_concede.pressed.connect(_on_concede_pressed)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)
	btn_sound_toggle.gui_input.connect(_on_sound_gui_input)
	btn_music_toggle.gui_input.connect(_on_music_gui_input)
	_update_sound_button_text()
	_update_music_button_text()
	btn_rematch.pressed.connect(_on_rematch_pressed)
	btn_end_menu.pressed.connect(_on_main_menu_pressed)

	# Connect hand right-click for card zoom (bind player_id to filter opponent's hand)
	player1_hand.hand_card_right_clicked.connect(_on_hand_card_right_clicked.bind(0))
	player2_hand.hand_card_right_clicked.connect(_on_hand_card_right_clicked.bind(1))

	# Listen for disconnects in multiplayer
	if is_multiplayer_game:
		NetworkManager.is_in_game = true
		_reconnect.setup()
		# Save reconnect session for app-restart recovery (online only)
		if NetworkManager.mode in [NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT, NetworkManager.Mode.ONLINE]:
			GameSettings.save_reconnect_session(
				NetworkManager.get_game_code(),
				NetworkManager.is_host(),
				NetworkManager.game_mode,
				NetworkManager.is_public_room,
				NetworkManager.room_token,
			)

	# Minimize chip: restores a "View Board"-minimized selection overlay
	_minimize_chip = MinimizeChip.new()
	_minimize_chip.pressed.connect(_on_minimize_chip_pressed)
	add_child(_minimize_chip)
	# Prompt overlays die silently on game end — drop the chip with them
	end_game_panel.visibility_changed.connect(func() -> void:
		if end_game_panel.visible:
			_clear_minimize_chip())
	_hand.setup()
	opponent_hand_button_stack.visible = not is_multiplayer_game

	# Bot card visibility toggle
	if is_bot_game:
		_setup_bot_visibility_toggle()

	# Lobby-bot mode: show waiting banner + listen for arriving opponent
	if _is_lobby_bot:
		_setup_lobby_bot_ui()

	# Server-stall indicator (dedicated server only; relay/LAN games route
	# through a player-host and disconnects are covered by ReconnectController)
	if NetworkManager.mode == NetworkManager.Mode.ONLINE:
		_setup_pending_indicator()

	# Save game button (solo/bot only)
	if not is_multiplayer_game:
		_setup_save_button()

	_setup_rematch_deck_select()

	# Connect discard view
	player1_board.discard_clicked.connect(_on_discard_clicked)
	player2_board.discard_clicked.connect(_on_discard_clicked)

	# Connect monster deck view
	player1_board.monster_deck_clicked.connect(_on_monster_deck_clicked)
	player2_board.monster_deck_clicked.connect(_on_monster_deck_clicked)

	# Connect zone stack view
	player1_board.zone_slot_clicked.connect(_on_zone_slot_clicked)
	player2_board.zone_slot_clicked.connect(_on_zone_slot_clicked)
	player1_board.strategy_slot_clicked.connect(_on_strategy_slot_clicked)
	player2_board.strategy_slot_clicked.connect(_on_strategy_slot_clicked)

	# Connect card zoom (right-click)
	player1_board.zone_slot_right_clicked.connect(_on_zone_slot_right_clicked)
	player2_board.zone_slot_right_clicked.connect(_on_zone_slot_right_clicked)
	player1_board.strategy_slot_right_clicked.connect(_on_strategy_slot_right_clicked)
	player2_board.strategy_slot_right_clicked.connect(_on_strategy_slot_right_clicked)

	# Enable BBCode on log for hoverable card links (no underline)
	log_output.bbcode_enabled = true
	log_output.meta_underlined = false
	log_output.meta_hover_started.connect(_on_log_meta_hover_started)
	log_output.meta_hover_ended.connect(_on_log_meta_hover_ended)
	log_output.meta_clicked.connect(_on_log_meta_clicked)

	# Hide overlays and prompts
	end_game_panel.visible = false
	action_prompt_panel.visible = false

	# Ensure overlays render above hand cards (which have incrementing z_index)
	end_game_panel.z_index = 100

	# Leave game confirmation dialog
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = tr("STR_GB_LEAVE_TITLE")
	_leave_dialog.dialog_text = tr("STR_GB_LEAVE_PROMPT")
	_leave_dialog.ok_button_text = tr("STR_GB_LEAVE_OK")
	_leave_dialog.cancel_button_text = tr("STR_COMMON_CANCEL")
	_leave_dialog.confirmed.connect(_on_main_menu_pressed)
	add_child(_leave_dialog)

	# Card hover preview panel (right side of screen)
	_preview_container = Control.new()
	_preview_container.anchor_left = 0.75
	_preview_container.anchor_right = 0.995
	_preview_container.anchor_top = 0.05
	_preview_container.anchor_bottom = 0.75
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_container.z_index = 100
	_preview_container.visible = false
	add_child(_preview_container)

	_preview_bg = Panel.new()
	_preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	_preview_bg.add_theme_stylebox_override("panel", bg_style)
	_preview_container.add_child(_preview_bg)

	_preview_card = card_scene.instantiate()
	_preview_card.drag_enabled = false
	_preview_card.hover_scale = 1.0
	_preview_card.hover_lift = 0.0
	_preview_container.add_child(_preview_card)
	_set_mouse_filter_ignore_recursive(_preview_card)

	player1_board.card_preview_requested.connect(_show_card_preview)
	player2_board.card_preview_requested.connect(_show_card_preview)
	player1_board.card_preview_cleared.connect(_hide_card_preview)
	player2_board.card_preview_cleared.connect(_hide_card_preview)

	# Position hands over hand spaces (deferred so layout is resolved)
	call_deferred("_position_hands")

	# Re-position hands whenever player boards resize (stretch ratio changes, etc.)
	player1_board.resized.connect(func(): call_deferred("_position_hands"))
	player2_board.resized.connect(func(): call_deferred("_position_hands"))

	# Apply mobile layout adjustments (deferred so containers are resolved)
	if GameSettings.use_mobile_layout:
		_is_mobile_layout = true
		call_deferred("_apply_mobile_layout")
	else:
		_apply_desktop_hand_button_stacks()

	# Initial board sync and start (host/solo only)
	if turn_manager:
		call_deferred("_start_game")
	else:
		_disable_all_buttons()


# Per-player auto settings — owned by TurnTrackerModule (forwarding property
# for the confirmation-flow readers)
var _player_settings: Array[Dictionary]:
	get: return _tracker.player_settings


func _start_game() -> void:
	# Loaded from save: skip first-player choice, jump to saved turn
	if _loaded_from_save:
		_loaded_from_save = false
		_apply_gradients_and_sync()
		SfxManager.play("game_setup")
		var saved_pid: int = turn_manager.game_state.current_player_id
		var saved_phase: CardEnums.GamePhase = turn_manager.game_state.current_phase
		var saved_sub: int = turn_manager.game_state.current_sub_phase
		# If already past main-phase resolve effects, skip to player actions.
		# Otherwise run main-phase resolve effects from the start of the sub-phase.
		var skip_effects: bool = saved_phase == CardEnums.GamePhase.MAIN and saved_sub >= 1
		turn_manager.resume_to_main_phase(saved_pid, not skip_effects)
		return

	if is_bot_game:
		# Solo v Bot: let the human choose who goes first
		SfxManager.play("game_start")
		_first_player.start_choice(0)

		while _first_player.result < 0:
			await Engine.get_main_loop().process_frame

		_first_player.finish()
		_first_player_id = _first_player.result
		_apply_gradients_and_sync()
		SfxManager.play("game_setup")
		turn_manager.start_game(_first_player.result)
		return

	if not is_multiplayer_game:
		# Solo: no need to choose, player 1 always goes first
		_first_player_id = 0
		_apply_gradients_and_sync()
		SfxManager.play("game_setup")
		turn_manager.start_game(0)
		return

	# Multiplayer: randomly select which player gets to choose who goes first
	var chooser_id := randi() % 2

	_on_log_message(GameLog.coin_flip_won(chooser_id))

	if chooser_id != local_player_id:
		# The chooser is the remote client — send RPC, show waiting state locally
		_first_player.start_waiting()
		_first_player.chooser_id = chooser_id
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == chooser_id:
				RpcLogger.log_send("first_player_choice_requested", 0)
				_sync._rpc_first_player_choice_requested.rpc_id(peer_id)
	else:
		# Host is the chooser — tell the client to wait
		_first_player.start_choice(chooser_id)
		RpcLogger.log_send("first_player_waiting", 0)
		_sync._rpc_first_player_waiting.rpc()

	# Wait for the choice to resolve
	while _first_player.result < 0:
		await Engine.get_main_loop().process_frame

	_first_player.finish()
	# Tell the client to restore its action panel (waiting client never gets cleanup)
	RpcLogger.log_send("cleanup_first_player", 0)
	_sync._rpc_cleanup_first_player.rpc()
	_apply_gradients_and_sync()
	_first_player_id = _first_player.result
	_on_log_message(GameLog.first_player_chose(_first_player.result, true))
	SfxManager.play("game_start")
	turn_manager.start_game(_first_player.result)


func _setup_replay_recorder() -> void:
	_session.setup_replay_recorder(is_bot_game)


func _apply_bot_seed() -> void:
	var s: int = NetworkManager.bot_seed
	print("[_apply_bot_seed] Entry: NetworkManager.bot_seed=%d, _bot_seed_was_explicit=%s" % [s, _bot_seed_was_explicit])
	_bot_seed_was_explicit = s >= 0
	if s < 0:
		# Auto-generate a seed from the current unseeded RNG
		s = randi()
		print("[_apply_bot_seed] Auto-generated seed: %d" % s)
	NetworkManager.bot_seed = s
	seed(s)
	print("[Bot] RNG seed: %d" % s)
	_on_log_message(GameLog.seed_announce(s))


func _setup_bot() -> void:
	_session.setup_bot(local_player_id)
	for i in range(2):
		if i < _turn_tracker_headers.size():
			_turn_tracker_headers[i].text = GameLog.player_name(i)


func _setup_bot_visibility_toggle() -> void:
	_bot_visibility_button = Button.new()
	_bot_visibility_button.text = tr("STR_GB_SHOW_BOT_CARDS")
	_bot_visibility_button.toggle_mode = true
	_bot_visibility_button.custom_minimum_size = Vector2(140, 36)
	_bot_visibility_button.toggled.connect(_on_bot_visibility_toggled)
	add_child(_bot_visibility_button)


func _on_bot_visibility_toggled(toggled_on: bool) -> void:
	_bot_cards_visible = toggled_on
	_bot_visibility_button.text = tr("STR_GB_HIDE_BOT_CARDS") if toggled_on else tr("STR_GB_SHOW_BOT_CARDS")
	if player2_board:
		player2_board.set_hand_face_down(not toggled_on)


func _setup_save_button() -> void:
	_save_game_button = Button.new()
	_save_game_button.text = tr("STR_GB_SAVE_GAME")
	_save_game_button.custom_minimum_size = Vector2(120, 36)
	_save_game_button.add_theme_font_size_override("font_size", 14)
	_save_game_button.pressed.connect(_on_save_game_pressed)
	add_child(_save_game_button)
	# Position below concede button
	_save_game_button.position = Vector2(10, 90)


func _on_save_game_pressed() -> void:
	if not turn_manager or not turn_manager.game_state:
		return
	SfxManager.play("ui_click")
	var mode_str: String
	match NetworkManager.mode:
		NetworkManager.Mode.SOLO: mode_str = "solo"
		NetworkManager.Mode.SOLO_BOT: mode_str = "solo_bot"
		_: mode_str = "solo"
	var diff_str: String = BotConfig.Difficulty.keys()[NetworkManager.bot_difficulty] if is_bot_game else ""
	var d_names: Array[String] = [
		DecklistManager.get_player_deck_name(0),
		DecklistManager.get_player_deck_name(1),
	]
	# Capture a seed from the current RNG state so loading this save produces
	# deterministic bot behavior (the original seed is stale — RNG has advanced).
	var save_seed: int = randi()
	print("[Save] Capturing game_seed=%d for save file" % save_seed)
	var data := GameSerializer.serialize_game_state(turn_manager.game_state, _first_player_id, mode_str, diff_str, d_names, save_seed)
	var path := GameSerializer.save_game_to_file(data)
	if not path.is_empty():
		_save_game_button.text = tr("STR_GB_SAVED")
		_save_game_button.disabled = true
		# Re-enable after 2 seconds
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(_save_game_button):
				_save_game_button.text = tr("STR_GB_SAVE_GAME")
				_save_game_button.disabled = false
		)


func _apply_gradients_and_sync() -> void:
	for i in range(turn_manager.game_state.players.size()):
		var player: PlayerState = turn_manager.game_state.players[i]
		var board = player1_board if i == 0 else player2_board
		if not player.current_monster.is_empty():
			board.apply_monster_gradient(player.current_monster)
	_sync_boards()


# First-player RPC shims — bodies live on FirstPlayerUI
func _rpc_first_player_waiting() -> void:
	_first_player.rpc_waiting()


func _rpc_first_player_choice_requested() -> void:
	_first_player.rpc_choice_requested()


func _rpc_first_player_choice_resolved(chosen_id: int) -> void:
	_first_player.rpc_choice_resolved(chosen_id)


func _rpc_cleanup_first_player() -> void:
	_first_player.rpc_cleanup()


func _arrange_for_local_player() -> void:
	if local_player_id != 1:
		return

	var board_column := $VBoxContainer/BoardArea/BoardColumn

	# Swap hand spaces and boards: local (P2) to bottom, opponent (P1) to top
	# Default order: P2HandSpace(0), P2Board(1), Divider(2), P1Board(3), P1HandSpace(4)
	# Target order:  P1HandSpace(0), P1Board(1), Divider(2), P2Board(3), P2HandSpace(4)
	var divider := board_column.get_node("Divider")
	board_column.move_child(player1_hand_space, 0)
	board_column.move_child(player1_board, 1)
	board_column.move_child(divider, 2)
	board_column.move_child(player2_board, 3)
	board_column.move_child(player2_hand_space, 4)

	# Toggle mirroring (P1 now at top needs mirroring, P2 at bottom doesn't)
	player1_board.toggle_mirrored()
	player2_board.toggle_mirrored()

	# Swap turn tracker: local player (P2) to bottom, opponent (P1) to top
	var tracker := $VBoxContainer/BoardArea/RightSpacer/TurnTracker
	var children: Array[Node] = []
	for child in tracker.get_children():
		children.append(child)
	var sep_idx := -1
	for i in range(children.size()):
		if children[i].name == "Separator":
			sep_idx = i
			break
	# Reorder: P1 section, separator, P2 section
	var new_order: Array[Node] = []
	new_order.append_array(children.slice(sep_idx + 1))
	new_order.append(children[sep_idx])
	new_order.append_array(children.slice(0, sep_idx))
	for i in range(new_order.size()):
		tracker.move_child(new_order[i], i)


func _position_hands() -> void:
	var local_hand: Node2D
	var local_space: Control
	var opponent_hand: Node2D
	var opponent_space: Control

	if local_player_id == 0:
		local_hand = player1_hand
		local_space = player1_hand_space
		opponent_hand = player2_hand
		opponent_space = player2_hand_space
	else:
		local_hand = player2_hand
		local_space = player2_hand_space
		opponent_hand = player1_hand
		opponent_space = player1_hand_space

	# On mobile the action panel is full-width at the bottom, so hand can be centered.
	# On desktop, shift hand left to avoid the right-side action panel.
	var hand_center_x: float = 0.5 if _is_mobile_layout else 0.35
	var hand_width_pct: float = 0.92 if _is_mobile_layout else 0.95
	# Cap mobile hand width so cards don't cover action buttons
	const MOBILE_MAX_HAND_WIDTH := 700.0
	var mobile_hand_expand := 120.0 # Smaller expand offset on mobile to avoid obscuring board

	# On mobile, center hands on the viewport (scene) center.
	var viewport_center_x := get_viewport().get_visible_rect().size.x / 2.0

	# Local player hand: visible, centered in hand space
	if local_space and local_hand:
		var rect := local_space.get_global_rect()
		var expand_offset := mobile_hand_expand if _is_mobile_layout else HAND_EXPAND_OFFSET
		var y_offset := -expand_offset if _hand_expanded else 0.0
		var center_x := viewport_center_x if _is_mobile_layout else rect.position.x + rect.size.x * hand_center_x
		# Cards are positioned by top-left corner, so the visual center of the
		# arc is shifted right by half a card width. Compensate on mobile.
		if _is_mobile_layout and not local_hand.managed_cards.is_empty():
			var c: Control = local_hand.managed_cards[0]
			center_x -= c.size.x * c.scale.x / 2.0
		local_hand.global_position = Vector2(center_x, rect.position.y + rect.size.y / 2.0 + y_offset)
		var width := rect.size.x * hand_width_pct
		if _is_mobile_layout:
			width = minf(width, MOBILE_MAX_HAND_WIDTH)
		local_hand.max_width = width
		local_hand.arrange_cards(false)

		# Position local hand button stack at the bottom, left of the max-width hand edge
		if _is_mobile_layout and not local_hand.managed_cards.is_empty():
			var hand_stack := $HandButtonStack as HBoxContainer
			var stack_w := 150.0
			var stack_h := 60.0
			var cards_left: float = center_x - width / 2.0
			hand_stack.anchor_left = 0.0
			hand_stack.anchor_right = 0.0
			hand_stack.anchor_top = 1.0
			hand_stack.anchor_bottom = 1.0
			var min_left := maxf(20.0, _mobile._safe_left + 4.0)
			hand_stack.offset_left = maxf(min_left, cards_left - stack_w)
			hand_stack.offset_right = hand_stack.offset_left + stack_w
			var bot_pad := maxf(20.0, _mobile._safe_bottom + 4.0)
			hand_stack.offset_top = - (stack_h + bot_pad - 4.0)
			hand_stack.offset_bottom = - bot_pad

			# Position board view toggle directly above the hand stack
			if _mobile._mobile_view_toggle_btn:
				var view_gap := 16.0
				var view_w := 55.0
				var view_h := 60.0
				_mobile._mobile_view_toggle_btn.offset_left = hand_stack.offset_left
				_mobile._mobile_view_toggle_btn.offset_right = hand_stack.offset_left + view_w
				_mobile._mobile_view_toggle_btn.offset_bottom = hand_stack.offset_top - view_gap
				_mobile._mobile_view_toggle_btn.offset_top = _mobile._mobile_view_toggle_btn.offset_bottom - view_h

	# Opponent hand: mostly off-screen at top edge
	if opponent_space and opponent_hand:
		var rect := opponent_space.get_global_rect()
		var center_x := viewport_center_x if _is_mobile_layout else rect.position.x + rect.size.x * hand_center_x
		if _is_mobile_layout and not opponent_hand.managed_cards.is_empty():
			var c: Control = opponent_hand.managed_cards[0]
			center_x -= c.size.x * c.scale.x / 2.0
		var opp_base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
		var opp_y_offset := OPPONENT_HAND_EXPAND_OFFSET if _opponent_hand_expanded else 0.0
		opponent_hand.global_position = Vector2(center_x, opp_base_y + opp_y_offset)
		var width := rect.size.x * hand_width_pct
		if _is_mobile_layout:
			width = minf(width, MOBILE_MAX_HAND_WIDTH)
		opponent_hand.max_width = width
		opponent_hand.arrange_cards(false)

	# Position opponent hand button stack at top of screen, left of the max-width hand edge
	if _is_mobile_layout and opponent_hand and not opponent_hand.managed_cards.is_empty():
		var opp_stack := $OpponentHandButtonStack as HBoxContainer
		var stack_w := 150.0
		var stack_h := 60.0
		var opp_width: float = opponent_hand.max_width
		var opp_center_x := opponent_hand.global_position.x
		var cards_left: float = opp_center_x - opp_width / 2.0
		opp_stack.anchor_left = 0.0
		opp_stack.anchor_right = 0.0
		opp_stack.anchor_top = 0.0
		opp_stack.anchor_bottom = 0.0
		var opp_min_left := maxf(20.0, _mobile._safe_left + 4.0)
		opp_stack.offset_left = maxf(opp_min_left, cards_left - stack_w)
		opp_stack.offset_right = opp_stack.offset_left + stack_w
		# Use generous minimum top padding to avoid iOS screen-edge gesture zone
		# and to sit below the phase label
		var top_pad := maxf(40.0, _mobile._safe_top + 24.0)
		opp_stack.offset_top = top_pad
		opp_stack.offset_bottom = top_pad + stack_h

		# Bot visibility button below opponent hand stack
		if _bot_visibility_button:
			_bot_visibility_button.anchor_left = 0.0
			_bot_visibility_button.anchor_right = 0.0
			_bot_visibility_button.anchor_top = 0.0
			_bot_visibility_button.anchor_bottom = 0.0
			_bot_visibility_button.offset_left = opp_stack.offset_left
			_bot_visibility_button.offset_right = opp_stack.offset_right
			_bot_visibility_button.offset_top = top_pad + stack_h + 4.0
			_bot_visibility_button.offset_bottom = top_pad + stack_h + 4.0 + 36.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _is_mobile_layout:
			_mobile._apply_safe_area_insets()
		call_deferred("_position_hands")


func _fit_button_text(btn: Button, base_size: int = 18, min_size: int = 10) -> void:
	if not _is_mobile_layout:
		return
	btn.clip_text = true
	var font := btn.get_theme_font("font")
	# Account for Godot's internal button padding (~16px) plus corner radius inset
	var available_w := btn.size.x - 32.0
	var font_size := base_size
	while font_size > min_size:
		var text_w := font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if text_w <= available_w:
			break
		font_size -= 1
	btn.add_theme_font_size_override("font_size", font_size)


## Apply a tab/handle style to a button on a screen edge.
## edge_side: "left" = flush left edge, rounded right; "right" = flush right edge, rounded left.


static func _fmt_num(value: int) -> String:
	var negative := value < 0
	var s := str(absi(value))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return ("-" + result) if negative else result


func _apply_desktop_hand_button_stacks() -> void:
	# Stack buttons vertically on desktop between the hand and action panel.
	# Hide the HBoxContainers and reparent buttons to GameBoard for free positioning.
	$HandButtonStack.visible = false
	$OpponentHandButtonStack.visible = false

	var btn_w := 55.0
	var btn_h := 32.0
	var gap := 2.0
	var right_margin := 300.0 # Action panel left edge is at -270

	# Reparent to GameBoard so HBoxContainer can't override layout
	hand_toggle_button.reparent(self )
	sort_hand_button.reparent(self )
	opponent_hand_toggle_button.reparent(self )
	opponent_sort_hand_button.reparent(self )

	# Reset minimum sizes from .tscn so offset-based sizing works
	for btn: Button in [hand_toggle_button, sort_hand_button,
			opponent_hand_toggle_button, opponent_sort_hand_button]:
		btn.custom_minimum_size = Vector2.ZERO

	# Local player — bottom-right, stacked vertically
	for btn: Button in [hand_toggle_button, sort_hand_button]:
		btn.anchor_left = 1.0
		btn.anchor_right = 1.0
		btn.anchor_top = 1.0
		btn.anchor_bottom = 1.0
	hand_toggle_button.offset_left = - (right_margin + btn_w)
	hand_toggle_button.offset_right = - right_margin
	hand_toggle_button.offset_bottom = - (btn_h + gap + 10.0)
	hand_toggle_button.offset_top = hand_toggle_button.offset_bottom - btn_h
	sort_hand_button.offset_left = - (right_margin + btn_w)
	sort_hand_button.offset_right = - right_margin
	sort_hand_button.offset_bottom = -10.0
	sort_hand_button.offset_top = sort_hand_button.offset_bottom - btn_h

	# Opponent — top-right, stacked vertically (hidden in multiplayer)
	for btn: Button in [opponent_hand_toggle_button, opponent_sort_hand_button]:
		btn.visible = not is_multiplayer_game
		btn.anchor_left = 1.0
		btn.anchor_right = 1.0
		btn.anchor_top = 0.0
		btn.anchor_bottom = 0.0
	opponent_hand_toggle_button.offset_left = - (right_margin + btn_w)
	opponent_hand_toggle_button.offset_right = - right_margin
	opponent_hand_toggle_button.offset_top = 10.0
	opponent_hand_toggle_button.offset_bottom = 10.0 + btn_h
	opponent_sort_hand_button.offset_left = - (right_margin + btn_w)
	opponent_sort_hand_button.offset_right = - right_margin
	opponent_sort_hand_button.offset_top = 10.0 + btn_h + gap
	opponent_sort_hand_button.offset_bottom = 10.0 + btn_h * 2 + gap

	# Bot visibility button below sort button
	if _bot_visibility_button:
		_bot_visibility_button.anchor_left = 1.0
		_bot_visibility_button.anchor_right = 1.0
		_bot_visibility_button.anchor_top = 0.0
		_bot_visibility_button.anchor_bottom = 0.0
		var bot_top := 10.0 + btn_h * 2 + gap * 2
		_bot_visibility_button.offset_left = - (right_margin + btn_w)
		_bot_visibility_button.offset_right = - right_margin
		_bot_visibility_button.offset_top = bot_top
		_bot_visibility_button.offset_bottom = bot_top + btn_h
		_bot_visibility_button.custom_minimum_size = Vector2.ZERO


# --- State access helpers (work for both host and client) ---

func _get_current_pid() -> int:
	if turn_manager:
		return turn_manager.game_state.current_player_id
	return _client_current_player_id


func _get_player_state(pid: int) -> PlayerState:
	if turn_manager:
		return turn_manager.game_state.players[pid]
	return _client_players[pid]


func _get_current_player() -> PlayerState:
	return _get_player_state(_get_current_pid())


func _get_opponent_player() -> PlayerState:
	return _get_player_state(1 - _get_current_pid())


# --- Action submission (routes to TurnManager or RPC) ---

func _submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	_action_pending = true
	_action_submitted_ms = Time.get_ticks_msec()
	_disable_all_buttons()
	# Clear the hand-card selection border on every submission. In multiplayer the
	# host's _rpc_receive_action_context handles this, but solo never gets that
	# RPC so a clicked-then-played card kept its yellow HighlightOverlay forever.
	_clear_card_highlight()
	if not is_multiplayer_game or NetworkManager.is_host():
		turn_manager.submit_action(action, params)
	else:
		var params_json := JSON.stringify(params) if not params.is_empty() else ""
		RpcLogger.log_send("submit_action", 4 + params_json.length())
		_sync._rpc_submit_action.rpc_id(NetworkManager.host_peer_id, int(action), params_json)


## Tracker shim — display logic lives on TurnTrackerModule (sync and a few
## board paths still call this).
func _update_turn_tracker(player_id: int, phase: CardEnums.GamePhase, sub_phase: int = 0) -> void:
	_tracker.update_turn_tracker(player_id, phase, sub_phase)


# --- Signal handlers from TurnManager (host/solo only) ---

func _on_phase_started(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()
	_broadcast_state()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()
	_broadcast_state()


func _on_sub_phase_changed(_sub_index: int) -> void:
	# TurnTrackerModule updates current_sub_phase + display via its own
	# subscription (connected before this handler, so the broadcast below
	# serializes the new sub-phase).
	_broadcast_state()


func _on_turn_started(player_id: int) -> void:
	_sync_boards()
	_update_hand_visibility(player_id)
	# Don't broadcast here — current_phase is still END from the previous turn.
	# The subsequent phase_started(START) signal handles the broadcast with correct state.

	# Stats: accumulate previous player's think time and start new timer
	var now := Time.get_ticks_msec()
	if _game_start_time_ms == 0:
		_game_start_time_ms = now
	elif _turn_start_time_ms > 0:
		var prev_player := 1 - player_id
		_player_elapsed_ms[prev_player] += now - _turn_start_time_ms
	_turn_start_time_ms = now


func _on_awaiting_action(valid_actions: Array) -> void:
	_action_pending = false
	_sync_boards()

	if is_bot_game and _get_current_pid() == bot_player.bot_player_id:
		_disable_all_buttons()
		return

	if is_multiplayer_game:
		_broadcast_state()
		_flush_broadcast() # Action context must arrive after state
		var active_id := turn_manager.game_state.current_player_id

		# Compute playable indices for the active player
		var playable := _sync.compute_playable_data()
		var actions_json := JSON.stringify(valid_actions)
		var playable_json := JSON.stringify(playable)

		if active_id == local_player_id:
			# Host's turn
			_client_playable = playable
			_update_action_buttons(valid_actions)
		else:
			# Client's turn — send context, disable host buttons
			_disable_all_buttons()
			_pending_interaction = {"method": "action_context", "args": [actions_json, playable_json], "player": active_id}
			for peer_id in NetworkManager.peer_player_map:
				if NetworkManager.peer_player_map[peer_id] == active_id:
					RpcLogger.log_send("receive_action_context", actions_json.length() + playable_json.length())
					_sync._rpc_receive_action_context.rpc_id(peer_id, actions_json, playable_json)
	else:
		_update_action_buttons(valid_actions)


func _on_game_ended(winner_id: int, reason_key: String) -> void:
	_end_game.on_game_ended(winner_id, reason_key)


func _on_confirmation_requested(prompt: String, setting: String) -> void:
	var current_pid: int = turn_manager.game_state.current_player_id
	if is_bot_game and current_pid == bot_player.bot_player_id:
		return
	if is_multiplayer_game and current_pid != local_player_id:
		_flush_broadcast()
		_pending_interaction = {"method": "confirmation", "args": [prompt, setting], "player": current_pid}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == current_pid:
				RpcLogger.log_send("confirmation_requested", prompt.length() + setting.length())
				_sync._rpc_confirmation_requested.rpc_id(peer_id, prompt, setting)
		return
	# Local player: check their per-player settings
	if _player_settings[current_pid].get(setting, false):
		_session.player_input.resolve_confirmation()
		return
	_show_confirmation(prompt)


func _show_confirmation(prompt: String) -> void:
	_awaiting_confirmation = true
	_disable_all_buttons()
	btn_confirm.text = _resolve_translated_text(prompt)
	_fit_button_text(btn_confirm)
	btn_confirm.disabled = false
	await btn_confirm.pressed
	_awaiting_confirmation = false
	btn_confirm.disabled = true
	btn_confirm.add_theme_font_size_override("font_size", 18)
	if turn_manager:
		_session.player_input.resolve_confirmation()
	elif is_multiplayer_game:
		RpcLogger.log_send("confirmation_resolved", 0)
		_sync._rpc_confirmation_resolved.rpc_id(NetworkManager.host_peer_id)


func _on_state_changed() -> void:
	_sync_boards()
	if not _discard_selecting:
		_update_hand_visibility(_get_current_pid())
	_broadcast_state()
	if replay_recorder:
		replay_recorder.on_state_changed()


func _on_log_message(message) -> void:
	_log_chat.append_message(message)


## Defensive client-side fallback: log lines and prompts ship from the host
## as already-translated strings (host's `tr()` baked the result into the RPC
## payload). If the host's `tr()` ever returns the key literally — e.g. a
## transient TranslationServer state or a build/version drift — the client
## otherwise displays "STR_..." verbatim. Re-running `tr()` on the local side
## resolves it when the key exists in our translation table.
func _resolve_translated_text(text: String) -> String:
	if not text.begins_with("STR_"):
		return text
	# tr() expects no leading/trailing whitespace to find a match
	var stripped := text.strip_edges()
	var translated := tr(stripped)
	if translated == stripped:
		return text
	return text.replace(stripped, translated)


func _dispatch_chat(text: String) -> void:
	_log_chat.dispatch_chat(text)


func _on_discard_reshuffled(moved_cards: Array, player_id: int) -> void:
	# Discard (public) → deck (private): log the move for both players, with a
	# clickable snapshot of what was shuffled in. Fires for effect-driven shuffles
	# and for the automatic reshuffle when drawing from an empty deck.
	var ids: Array = []
	for card in moved_cards:
		ids.append(CardUtils.base_id(card))
	_on_log_message(GameLog.effect_shuffled_discard_into_deck(player_id, ids))


# --- Action handler visual feedback ---

func _on_play_cancelled(player_id: int) -> void:
	# Reset the dragged card's scale/state and tween it back to its slot.
	_clear_card_highlight()
	var board: Control = player1_board if player_id == 0 else player2_board
	if board and board.hand_manager:
		for card in board.hand_manager.get_cards():
			card.is_locked_in_zone = false
			if card.is_snap_previewing:
				card.end_snap_preview()
			if card.tween:
				card.tween.kill()
			card.scale = card.original_scale
		board.hand_manager.exit_selection_mode()
		# Drop-handled drag skipped arrange_cards, so the dragged card is still
		# at its drop position. Move only that card back to its slot — leave
		# the rest of the player's hand order untouched.
		board.hand_manager.restore_drop_handled_card_position()
	# Sync boards in case the cost prompt changed hand/discard state
	_sync_boards()


func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	_sync_boards()
	_broadcast_state()


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	_sync_boards()
	_broadcast_state()


func _on_battle_card_crushed(player_id: int, zone_index: int, card: Dictionary) -> void:
	_on_log_message(GameLog.battle_card_crushed(card.get("id", ""), player_id, zone_index))
	_sync_boards()
	_broadcast_state()


func _on_counter_succeeded(player_id: int, total_cp: int, threat: int, rage_threat: int, effect_threat: int) -> void:
	_on_log_message(GameLog.counter_succeeded(player_id, total_cp, threat, rage_threat, effect_threat))
	_sync_boards()
	_broadcast_state()


func _on_counter_failed(player_id: int, total_cp: int, threat: int, rage_threat: int, effect_threat: int) -> void:
	_on_log_message(GameLog.counter_failed(player_id, total_cp, threat, rage_threat, effect_threat))


func _on_counter_immunity_triggered(player_id: int, total_cp: int, threshold: int) -> void:
	_on_log_message(GameLog.counter_immunity(player_id, total_cp, threshold))


func _on_counter_prevented(player_id: int) -> void:
	_on_log_message(GameLog.counter_prevented(player_id))


func _threat_mod_for(pid: int) -> int:
	## Effect-driven threat modifier for a player, working on both host (live
	## effect handler) and client (synced modifiers from the last broadcast).
	if turn_manager and turn_manager.effect_handler:
		return turn_manager.effect_handler.get_threat_level_modifier(pid)
	if pid >= 0 and pid < _client_threat_modifiers.size():
		return int(_client_threat_modifiers[pid])
	return 0


func _on_monster_countered(_player_id: int, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	_sync_boards()
	_broadcast_state()


# --- Sound toggle ---

const _VOLUME_VALUE_KEYS := ["STR_VOL_OFF", "25%", "50%", "75%", "100%"]

func _on_sound_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameSettings.sound_volume = (GameSettings.sound_volume + 1) % 5
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameSettings.sound_volume = (GameSettings.sound_volume + 4) % 5
		else:
			return
		GameSettings.save()
		_update_sound_button_text()
		SfxManager.play("ui_click")


func _on_sound_toggle_pressed() -> void:
	GameSettings.sound_volume = (GameSettings.sound_volume + 1) % 5
	GameSettings.save()
	_update_sound_button_text()


func _update_sound_button_text() -> void:
	var label: String = tr("STR_GB_SOUND_FMT").replace("{VAL}", tr(_VOLUME_VALUE_KEYS[GameSettings.sound_volume]))
	if btn_sound_toggle:
		btn_sound_toggle.text = label
	if _mobile._mobile_sound_button:
		_mobile._mobile_sound_button.text = label


# --- Music toggle ---


func _on_music_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameSettings.music_volume = (GameSettings.music_volume + 1) % 5
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameSettings.music_volume = (GameSettings.music_volume + 4) % 5
		else:
			return
		SfxManager.play("ui_click")
		GameSettings.save()
		MusicManager.set_volume(GameSettings.music_volume)
		_update_music_button_text()


func _on_music_toggle_pressed() -> void:
	GameSettings.music_volume = (GameSettings.music_volume + 1) % 5
	GameSettings.save()
	MusicManager.set_volume(GameSettings.music_volume)
	_update_music_button_text()


func _update_music_button_text() -> void:
	var label: String = tr("STR_GB_MUSIC_FMT").replace("{VAL}", tr(_VOLUME_VALUE_KEYS[GameSettings.music_volume]))
	if btn_music_toggle:
		btn_music_toggle.text = label
	if _mobile._mobile_music_button:
		_mobile._mobile_music_button.text = label


# --- Bug report ---

func _on_bug_report_pressed() -> void:
	var body := _build_bug_report_body()
	var url := "https://github.com/hunterdurbin/godzilla-sim/issues/new?labels=bug&title=Bug+Report&body=" + body.uri_encode()
	OS.shell_open(url)


func _build_bug_report_body() -> String:
	return BugReport.build_body(self)


# --- Concede / Main Menu ---

func _on_concede_pressed() -> void:
	_end_game.on_concede_pressed()


func _rpc_concede() -> void:
	_end_game.rpc_concede()


func _on_main_menu_pressed() -> void:
	_reconnect.hide_overlay()
	# Lobby-bot mode: keep the relay alive and return to PublicLobby instead of MainMenu.
	if _is_lobby_bot:
		NetworkManager.exit_lobby_bot_game()
		NetworkManager.change_scene("res://scenes/ui/PublicLobby.tscn")
		return
	if is_multiplayer_game:
		var connected := multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		if end_game_panel.visible:
			# Game already over — notify rematch declined
			if connected:
				RpcLogger.log_send("rematch_declined", 0)
				_sync._rpc_rematch_declined.rpc()
		elif connected and turn_manager and not turn_manager.is_game_over:
			# Mid-game exit counts as concession
			if NetworkManager.is_host():
				var loser_id := local_player_id
				var winner_id := 1 - loser_id
				turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))
			else:
				RpcLogger.log_send("concede", 0)
				_sync._rpc_concede.rpc_id(NetworkManager.host_peer_id)
		GameSettings.clear_reconnect_session()
		NetworkManager.is_in_game = false
		NetworkManager.disconnect_game()
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _on_rematch_pressed() -> void:
	_end_game.on_rematch_pressed()


func _execute_rematch() -> void:
	# 1. Hide end game panel and reset rematch flags
	end_game_panel.visible = false
	_rematch_requested = false
	_opponent_rematch_requested = false
	_game_ended_by_disconnect = false
	_rematch_deck_select.visible = false
	_rematch_deck_select.set_disabled(false)
	_rematch_deck_changed = false
	_rematch_deck_name = ""
	_reconnect_cumulative_seconds = 0.0
	_pending_interaction = {}
	# Re-save session with fresh timestamp for the new game
	if is_multiplayer_game and NetworkManager.mode in [NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT, NetworkManager.Mode.ONLINE]:
		GameSettings.save_reconnect_session(
			NetworkManager.get_game_code(),
			NetworkManager.is_host(),
			NetworkManager.game_mode,
			NetworkManager.is_public_room,
			NetworkManager.room_token,
		)

	# 2. Clear visual state on both boards
	player1_board.reset_visuals()
	player2_board.reset_visuals()

	# 3. Clear hands
	player1_hand.clear_cards(true)
	player2_hand.clear_cards(true)

	# 4. Reset game_board state variables
	_action_pending = false
	_awaiting_confirmation = false
	_selection.reset_for_rematch()
	_first_player.choosing = false
	_first_player.chooser_id = -1
	_first_player.result = -1
	_first_player_id = 0
	_hand_expanded = false
	_opponent_hand_expanded = false
	_sync.reset_for_rematch()
	_client_gradients_applied = false
	_player_elapsed_ms = [0, 0]
	_turn_start_time_ms = 0
	_game_start_time_ms = 0
	_stats_uploaded = false

	# 5. Restore action panel and hide overlays
	_first_player.finish()
	_cleanup_choice_selection()
	_selection._cleanup_prompt_previews()
	_effect_stack.reset()
	_clear_card_attention()
	_update_tracker_collapse()
	_set_action_buttons_visible(true)
	action_prompt_panel.visible = false
	deck_search_overlay.visible = false
	deck_arrange_overlay.visible = false
	card_pool_select_overlay.visible = false
	_clear_minimize_chip()
	discard_view_overlay.visible = false
	monster_deck_view_overlay.visible = false
	zone_stack_view_overlay.visible = false
	card_zoom_overlay.visible = false

	# 6. Reset client state
	_client_players = [PlayerState.new(0), PlayerState.new(1)]
	_client_current_player_id = 0
	_client_turn_number = 0
	_client_phase = CardEnums.GamePhase.START
	_client_playable = {}
	_client_cp_modifiers = [0, 0]
	_client_threat_modifiers = [0, 0]
	_client_zone_cp_mods = [[], []]
	_client_strategy_cp_mods = [[], []]
	_client_zone_rank_mods = [[], []]
	_client_hand_rank_mods = [[], []]
	_client_monster_cp_mods = [0, 0]
	_client_modifier_breakdowns = {}

	# 7. Clear game log
	_log_tokens.clear()
	if log_output:
		log_output.clear()

	# 8. Reset turn tracker display
	_tracker.reset_for_rematch()

	# 9. Recreate TurnManager (host/solo only)
	if not is_multiplayer_game or NetworkManager.is_host():
		# Drop old TurnManager reference (RefCounted — will be GC'd)
		turn_manager = null
		await get_tree().process_frame

		# Solo v Bot: seed RNG for deterministic behavior
		if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
			if not _bot_seed_was_explicit:
				NetworkManager.bot_seed = -1
			_apply_bot_seed()
			# Re-pick the bot's deck from its random pool, if configured.
			# Empty pool → picker returns "" and we keep the previous deck.
			if GameSettings.bot_random_deck_enabled and GameSettings.bot_random_deck_on_rematch:
				var picked := GameSettings.pick_weighted_random_deck()
				if not picked.is_empty():
					DecklistManager.select_deck_for_player(1, picked)

		_session.start_host_session(CardData, local_player_id)
		for i in range(2):
			if i < _turn_tracker_headers.size():
				_turn_tracker_headers[i].text = GameLog.player_name(i)

		# Reconnect turn manager signals
		turn_manager.phase_started.connect(_on_phase_started)
		turn_manager.phase_ended.connect(_on_phase_ended)
		turn_manager.sub_phase_changed.connect(_on_sub_phase_changed)
		turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		turn_manager.turn_started.connect(_on_turn_started)
		turn_manager.player_input.confirmation_requested.connect(_on_confirmation_requested)

		# Reconnect action handler signals
		turn_manager.events.battle_card_played.connect(_on_battle_card_played)
		turn_manager.events.monster_advanced.connect(_on_monster_advanced)
		turn_manager.events.battle_card_crushed.connect(_on_battle_card_crushed)
		turn_manager.events.counter_succeeded.connect(_on_counter_succeeded)
		turn_manager.events.play_cancelled.connect(_on_play_cancelled)
		turn_manager.events.counter_failed.connect(_on_counter_failed)
		turn_manager.events.counter_immunity_triggered.connect(_on_counter_immunity_triggered)
		turn_manager.events.counter_prevented.connect(_on_counter_prevented)
		turn_manager.events.monster_countered.connect(_on_monster_countered)

		# Reconnect effect handler signals
		turn_manager.action_handler.effect_handler.effect_zone_highlighted.connect(_on_effect_zone_highlighted)
		turn_manager.action_handler.effect_handler.effect_zone_unhighlighted.connect(_on_effect_zone_unhighlighted)
		turn_manager.action_handler.effect_handler.effect_card_highlighted.connect(_on_effect_card_highlighted)
		turn_manager.action_handler.effect_handler.effect_card_unhighlighted.connect(_on_effect_card_unhighlighted)

		# Reconnect bot player for Solo v Bot mode
		if is_bot_game:
			_setup_bot()

		# Reconnect player state signals
		for player in turn_manager.game_state.players:
			player.hand_changed.connect(_on_state_changed)
			player.zones_changed.connect(_on_state_changed)
			player.rage_changed.connect(_on_state_changed.unbind(1))
			player.monster_changed.connect(_on_state_changed)
			player.discard_changed.connect(_on_state_changed)
			player.deck_changed.connect(_on_state_changed)
			player.strategy_zones_changed.connect(_on_state_changed)
			player.discard_reshuffled.connect(_on_discard_reshuffled.bind(player.player_id))

		# Set up replay recorder for the new game
		_setup_replay_recorder()

		# Start game (coin flip for multiplayer, immediate for solo)
		call_deferred("_start_game")
	else:
		# Client: just wait for state broadcasts from host
		_disable_all_buttons()


# --- Rematch deck select ---

func _setup_rematch_deck_select() -> void:
	_end_game.setup_rematch_deck_select()


func _populate_rematch_deck_select() -> void:
	_end_game.populate_rematch_deck_select()


# --- Rematch RPCs ---

## Rematch RPC shims — bodies live on EndGameController
func _rpc_rematch_requested() -> void:
	_end_game.rpc_rematch_requested()


func _rpc_rematch_with_deck(payload_json: String) -> void:
	_end_game.rpc_rematch_with_deck(payload_json)


func _rpc_execute_rematch() -> void:
	_end_game.rpc_execute_rematch()


func _rpc_rematch_declined() -> void:
	_end_game.rpc_rematch_declined()


# --- Button handlers ---


# --- Card selection flow ---


func _process(_delta: float) -> void:
	_update_mobile_chat_bar()
	_process_lobby_banner_tick()
	_process_pending_indicator()
	# Reconnect overlay display
	_reconnect.process_tick()
	if _reconnect.is_overlay_active():
		return # Skip normal drag processing while overlay is showing

	_selection.process_drag()


# Keep the floating chat bar docked just above the on-screen keyboard while it is visible.


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and chat_input.has_focus():
		if not chat_input.get_global_rect().has_point(event.global_position):
			chat_input.release_focus()

	# Tap outside the floating mobile chat bar dismisses it.
	if _mobile_chat_bar and _mobile_chat_bar.visible and event is InputEventMouseButton and event.pressed:
		if not _mobile_chat_bar.get_global_rect().has_point(event.global_position):
			_close_mobile_chat_bar()

	# Card zoom: pinch/pan/magnify/dismiss handling lives on the overlay
	if card_zoom_overlay.handle_input(event):
		get_viewport().set_input_as_handled()
		return

	# Dismiss overlays and skip optional prompts (priority order, topmost first)
	# Uses ui_cancel (ESC on keyboard, B/Circle on controller)
	if event.is_action_pressed("ui_cancel"):
		if card_zoom_overlay.visible:
			card_zoom_overlay.hide_zoom()
		elif deck_arrange_overlay.visible:
			pass # Mandatory — must confirm
		elif card_pool_select_overlay.visible:
			card_pool_select_overlay.try_skip()
		elif deck_search_overlay.visible:
			# ESC dismisses only when skip is allowed; otherwise the prompt is mandatory.
			deck_search_overlay.try_skip()
		elif discard_view_overlay.visible:
			discard_view_overlay.try_close()
		elif monster_deck_view_overlay.visible:
			monster_deck_view_overlay.try_close() # Refused during mandatory rank-up
		elif zone_stack_view_overlay.visible:
			zone_stack_view_overlay.try_close()
		elif _minimize_chip.visible:
			_restore_minimized_overlay()
		elif _choice_selecting:
			pass # Mandatory — must pick an option
		elif _hand_card_selecting and _hand_card_allow_skip:
			_skip_hand_card_selection()
		elif _zone_target_selecting and _zone_target_allow_skip:
			_skip_zone_target()
		elif waiting_for_card_select or waiting_for_zone_select:
			_clear_card_highlight()
			_cancel_selection()
			if turn_manager:
				_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
			else:
				_update_action_buttons(_client_playable.get("valid_actions", []))
		elif _confirming_pass:
			_cancel_pass_confirmation()
		else:
			_leave_dialog.popup_centered()
		get_viewport().set_input_as_handled()
		return

	# Handle arrange card drag via _input (reparenting breaks gui_input mouse grab)
	if deck_arrange_overlay.handle_drag_input(event):
		get_viewport().set_input_as_handled()
		return

	if not waiting_for_zone_select:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var board := _get_active_player_board()
		if not board:
			return

		var mouse_pos := get_global_mouse_position()
		for i in _zone_select_valid:
			var slot: Slot = board.zone_slots[i]
			var rect := Rect2(slot.global_position, slot.size)
			if rect.has_point(mouse_pos):
				var hand_idx: int = _find_hand_index_by_id(selected_card_id)
				_cancel_selection()
				get_viewport().set_input_as_handled()
				if hand_idx >= 0:
					_submit_action(CardEnums.ActionType.PLAY_BATTLE, {
						"hand_index": hand_idx,
						"zone_index": i
					})
				return


# --- Mobile shims: logic lives on MobileLayout ---

func _apply_mobile_layout() -> void:
	_mobile._apply_mobile_layout()


func _notify_mobile_log_chat() -> void:
	_mobile._notify_mobile_log_chat()


func _update_mobile_chat_bar() -> void:
	_mobile._update_mobile_chat_bar()


func _close_mobile_chat_bar() -> void:
	_mobile._close_mobile_chat_bar()


func _collapse_fab_instant() -> void:
	_mobile._collapse_fab_instant()


func _sync_mobile_cp_tray() -> void:
	_mobile._sync_mobile_cp_tray()


# --- Selection shims: logic lives on SelectionController ---

func _cancel_selection() -> void:
	_selection._cancel_selection()


func _update_action_buttons(valid_actions: Array) -> void:
	_selection._update_action_buttons(valid_actions)


func _disable_all_buttons() -> void:
	_selection._disable_all_buttons()


func _get_active_player_board() -> Control:
	return _selection._get_active_player_board()


func _find_hand_index_by_id(card_id: String) -> int:
	return _selection._find_hand_index_by_id(card_id)


func _clear_card_highlight() -> void:
	_selection._clear_card_highlight()


func _force_cleanup_discard_selection() -> void:
	_selection._force_cleanup_discard_selection()


func _skip_hand_card_selection() -> void:
	_selection._skip_hand_card_selection()


func _skip_zone_target() -> void:
	_selection._skip_zone_target()


func _cancel_pass_confirmation() -> void:
	_selection._cancel_pass_confirmation()


func _cleanup_choice_selection() -> void:
	_selection._cleanup_choice_selection()


func _on_hand_drag_started(card: Control) -> void:
	_selection._on_hand_drag_started(card)


func _on_hand_drag_ended(card: Control) -> void:
	_selection._on_hand_drag_ended(card)


# --- UI helpers ---

func _sync_boards() -> void:
	# Skip syncing the discarding player's board during discard selection
	# to avoid rebuilding the hand and invalidating selected card references
	var skip_p1 := _discard_selecting and _discard_player_id == 0
	var skip_p2 := _discard_selecting and _discard_player_id == 1
	if turn_manager and turn_manager.game_state:
		var state := turn_manager.game_state
		var eh := turn_manager.effect_handler
		var zone_cp_0: Array = eh.get_zone_cp_modifiers(0) if eh else []
		var zone_cp_1: Array = eh.get_zone_cp_modifiers(1) if eh else []
		var strat_cp_0: Array = eh.get_strategy_cp_modifiers(0) if eh else []
		var strat_cp_1: Array = eh.get_strategy_cp_modifiers(1) if eh else []
		var monster_cp_0: int = eh.get_monster_cp_modifier(0) if eh else 0
		var monster_cp_1: int = eh.get_monster_cp_modifier(1) if eh else 0
		var cp_mod_0: int = monster_cp_0
		var cp_mod_1: int = monster_cp_1
		for v in zone_cp_0: cp_mod_0 += v
		for v in zone_cp_1: cp_mod_1 += v
		for v in strat_cp_0: cp_mod_0 += v
		for v in strat_cp_1: cp_mod_1 += v
		var threat_mod_0: int = eh.get_threat_level_modifier(0) if eh else 0
		var threat_mod_1: int = eh.get_threat_level_modifier(1) if eh else 0
		var zone_rank_0: Array = eh.get_zone_rank_modifiers(0) if eh else []
		var zone_rank_1: Array = eh.get_zone_rank_modifiers(1) if eh else []
		var hand_rank_0: Array = _session.compute_hand_rank_mods(state.players[0]) if eh else []
		var hand_rank_1: Array = _session.compute_hand_rank_mods(state.players[1]) if eh else []
		if player1_board and not skip_p1:
			player1_board.sync_to_state(state.players[0], cp_mod_0, threat_mod_0, zone_cp_0, strat_cp_0, zone_rank_0, monster_cp_0, hand_rank_0)
		if player2_board and not skip_p2:
			player2_board.sync_to_state(state.players[1], cp_mod_1, threat_mod_1, zone_cp_1, strat_cp_1, zone_rank_1, monster_cp_1, hand_rank_1)
	elif not _client_players.is_empty():
		if player1_board and not skip_p1:
			player1_board.sync_to_state(_client_players[0], _client_cp_modifiers[0], _client_threat_modifiers[0], _client_zone_cp_mods[0], _client_strategy_cp_mods[0], _client_zone_rank_mods[0], _client_monster_cp_mods[0], _client_hand_rank_mods[0])
		if player2_board and not skip_p2:
			player2_board.sync_to_state(_client_players[1], _client_cp_modifiers[1], _client_threat_modifiers[1], _client_zone_cp_mods[1], _client_strategy_cp_mods[1], _client_zone_rank_mods[1], _client_monster_cp_mods[1], _client_hand_rank_mods[1])
	if _is_mobile_layout:
		_sync_mobile_cp_tray()
	call_deferred("_position_hands")


func _update_hand_visibility(_active_player_id: int) -> void:
	if is_multiplayer_game:
		# Multiplayer: local player always face-up, opponent always face-down
		if player1_board:
			player1_board.set_hand_face_down(local_player_id != 0)
		if player2_board:
			player2_board.set_hand_face_down(local_player_id != 1)
	elif is_bot_game:
		# Bot mode: P1 (human) face-up, P2 (bot) respects visibility toggle
		if player1_board:
			player1_board.set_hand_face_down(false)
		if player2_board:
			player2_board.set_hand_face_down(not _bot_cards_visible)
	else:
		# Solo: both hands always face-up
		if player1_board:
			player1_board.set_hand_face_down(false)
		if player2_board:
			player2_board.set_hand_face_down(false)


## Translate player.hand indices to managed_cards indices by matching card IDs


## Find a card's index in player.hand by its unique ID


# --- Drag-to-zone ---


# --- Deck search UI ---

# --- FAB (Floating Action Button) ---


# --- FAB Icon Drawing ---


func _temporarily_collapse_hand() -> void:
	_hand.temporarily_collapse_hand()


func _restore_expanded_hand() -> void:
	_hand.restore_expanded_hand()


func _temporarily_collapse_opponent_hand() -> void:
	_hand.temporarily_collapse_opponent_hand()


func _restore_expanded_opponent_hand() -> void:
	_hand.restore_expanded_opponent_hand()


## Router view-board hook: stash the overlay so ShowCards can re-show it.
func _on_overlay_view_board(overlay: Control) -> void:
	# One minimized overlay at a time: re-show any previously stashed one.
	if _view_board_source_overlay and _view_board_source_overlay != overlay:
		_restore_minimized_overlay()
	_view_board_source_overlay = overlay
	var info: Dictionary = overlay.get_minimize_info() if overlay.has_method("get_minimize_info") else {}
	var title: String = str(info.get("title", ""))
	if title.is_empty():
		title = tr("STR_GB_SHOW_CARDS")
	_minimize_chip.show_chip(title, int(info.get("count", 0)), _is_mobile_layout)
	# If the overlay becomes visible by ANY path (chip restore, reconnect
	# re-prompt, a second reveal reusing the same overlay), clear the chip.
	if not overlay.visibility_changed.is_connected(_on_minimized_overlay_visibility_changed):
		overlay.visibility_changed.connect(_on_minimized_overlay_visibility_changed)


func _on_minimize_chip_pressed() -> void:
	_restore_minimized_overlay()


func _restore_minimized_overlay() -> void:
	var overlay := _view_board_source_overlay
	_clear_minimize_chip()
	if overlay and is_instance_valid(overlay):
		overlay.visible = true


func _on_minimized_overlay_visibility_changed() -> void:
	if _view_board_source_overlay and _view_board_source_overlay.visible:
		_clear_minimize_chip()


func _clear_minimize_chip() -> void:
	if _minimize_chip:
		_minimize_chip.hide_chip()
	if _view_board_source_overlay and is_instance_valid(_view_board_source_overlay) \
			and _view_board_source_overlay.visibility_changed.is_connected(_on_minimized_overlay_visibility_changed):
		_view_board_source_overlay.visibility_changed.disconnect(_on_minimized_overlay_visibility_changed)
	_view_board_source_overlay = null


# --- Deck arrange overlay UI ---

# --- Card select overlay UI ---

# --- Hand discard selection UI ---


# --- Hand card selection UI (single-select for effects) ---


# --- Zone target selection UI ---


# --- Strategy target selection UI ---


# --- Standby ability order choice UI ---


func _on_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if is_multiplayer_game and pid != local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				RpcLogger.log_send("effect_zone_highlighted", 8)
				_sync._rpc_effect_zone_highlighted.rpc_id(peer_id, pid, zone_index)
		return
	_apply_zone_highlight(pid, zone_index, true)


func _on_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if is_multiplayer_game and pid != local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				RpcLogger.log_send("effect_zone_unhighlighted", 8)
				_sync._rpc_effect_zone_unhighlighted.rpc_id(peer_id, pid, zone_index)
		return
	_apply_zone_highlight(pid, zone_index, false)


func _apply_zone_highlight(pid: int, zone_index: int, highlighted: bool) -> void:
	var board: Control = player1_board if pid == 0 else player2_board
	if zone_index >= 0 and zone_index < board.zone_slots.size():
		var slot: Slot = board.zone_slots[zone_index]
		if slot and slot.held_card:
			slot.held_card.modulate = Color(1.2, 1.2, 0.6, 1.0) if highlighted else Color.WHITE


# --- Effect source card highlighting ---

func _on_effect_card_highlighted(pid: int, card_id: String) -> void:
	if is_multiplayer_game:
		for peer_id in NetworkManager.peer_player_map:
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_card_highlighted", 4 + card_id.length())
				_sync._rpc_effect_card_highlighted.rpc_id(peer_id, pid, card_id)
	_apply_card_highlight(pid, card_id, true)


func _on_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if is_multiplayer_game:
		for peer_id in NetworkManager.peer_player_map:
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_card_unhighlighted", 4 + card_id.length())
				_sync._rpc_effect_card_unhighlighted.rpc_id(peer_id, pid, card_id)
	_apply_card_highlight(pid, card_id, false)


func _apply_card_highlight(pid: int, card_id: String, highlighted: bool) -> void:
	if not highlighted:
		# Reset by node reference rather than card_id — the held_card's card_data
		# may have changed since highlight (e.g. evolution mutates the held node
		# in place), so an id-based lookup can miss the original target.
		if _highlighted_effect_card_node and is_instance_valid(_highlighted_effect_card_node):
			_highlighted_effect_card_node.modulate = Color.WHITE
		_highlighted_effect_card_node = null
		return
	var board: Control = player1_board if pid == 0 else player2_board
	var color := Color(1.2, 1.2, 0.6, 1.0)
	# Check zone slots (battle cards)
	for slot in board.zone_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == card_id:
			slot.held_card.modulate = color
			_highlighted_effect_card_node = slot.held_card
			return
	# Check strategy slots
	for slot in board.strategy_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == card_id:
			slot.held_card.modulate = color
			_highlighted_effect_card_node = slot.held_card
			return


# --- Prompt-driven chrome: tracker collapse + log dim ---

## Collapse the turn tracker to its one-line chip while the choice prompt or
## the effect-stack panel occupies the right edge.
func _update_tracker_collapse() -> void:
	_tracker.set_collapsed(_selection._choice_selecting or _effect_stack.has_rows())


func set_log_prompt_dim(active: bool) -> void:
	_log_chat.set_prompt_dim(active)


# --- Attention highlight (hovered effect-prompt / stack row) ---

func set_card_attention(loc: Dictionary, on: bool) -> void:
	## Pulse the attention border on the board card described by `loc`
	## (StandbyResolver.card_location_ref shape). Turning it off with a
	## non-empty loc only clears when that loc still matches the tracked
	## target, so a stale mouse_exited from one row can't kill the highlight
	## a newer row just turned on.
	if not on:
		if not loc.is_empty():
			if str(loc.get("kind", "")) == "discard":
				if _attention_discard_pid >= 0 and _attention_discard_pid != int(loc.get("player_id", -1)):
					return
			elif _attention_card_node and is_instance_valid(_attention_card_node):
				var node := _resolve_attention_card(loc)
				if node != null and node != _attention_card_node:
					return
		_clear_card_attention()
		return

	_clear_card_attention()
	if loc.is_empty():
		return
	var pid: int = int(loc.get("player_id", -1))
	if pid < 0 or pid > 1:
		return
	if str(loc.get("kind", "")) == "discard":
		var board: Control = player1_board if pid == 0 else player2_board
		board.highlight_discard_zone(true)
		_attention_discard_pid = pid
		return
	var target := _resolve_attention_card(loc)
	if target and target.has_method("set_attention_highlight"):
		# Ownership color language: cyan for the viewer's own effects, purple
		# for the opponent's (matches the stack panel's purple rows).
		var border := Color(0.7, 0.4, 1.0) if pid != local_player_id else Color(0.25, 0.85, 1.0)
		target.set_attention_highlight(true, border)
		_attention_card_node = target


func _clear_card_attention() -> void:
	if _attention_card_node and is_instance_valid(_attention_card_node):
		_attention_card_node.set_attention_highlight(false)
	_attention_card_node = null
	if _attention_discard_pid >= 0:
		var board: Control = player1_board if _attention_discard_pid == 0 else player2_board
		board.highlight_discard_zone(false)
		_attention_discard_pid = -1


func _resolve_attention_card(loc: Dictionary) -> Control:
	## Resolve a card_location_ref to its on-board Card node, verifying the
	## per-copy instance id and falling back to an id scan when the recorded
	## index went stale (the card moved since the ref was built).
	var pid: int = int(loc.get("player_id", -1))
	if pid < 0 or pid > 1:
		return null
	var board: Control = player1_board if pid == 0 else player2_board
	var index: int = int(loc.get("index", -1))
	var instance_id: String = str(loc.get("instance_id", ""))
	match str(loc.get("kind", "")):
		"monster":
			return board.monster_card
		"zone":
			if index >= 0 and index < board.zone_slots.size():
				var slot: Slot = board.zone_slots[index]
				if slot and slot.held_card and (instance_id.is_empty() or slot.held_card.card_data.get("id", "") == instance_id):
					return slot.held_card
		"strategy":
			if index >= 0 and index < board.strategy_slots.size():
				var strat_slot: Slot = board.strategy_slots[index]
				if strat_slot and strat_slot.held_card and (instance_id.is_empty() or strat_slot.held_card.card_data.get("id", "") == instance_id):
					return strat_slot.held_card
	if instance_id.is_empty():
		return null
	for slot in board.zone_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == instance_id:
			return slot.held_card
	for slot in board.strategy_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == instance_id:
			return slot.held_card
	return null


# --- Discard view UI ---

func _on_discard_clicked(pid: int) -> void:
	var player := _get_player_state(pid)
	var cards: Array[Dictionary] = player.discard_pile.duplicate(true)
	cards.reverse()
	var pname := GameLog.player_name(pid)
	discard_view_overlay.show_cards(cards, tr("STR_GB_DISCARD_TITLE_FMT") % [pname, cards.size()])


# --- Monster deck view UI ---

func _on_monster_deck_clicked(pid: int) -> void:
	# Only allow viewing your own monster deck
	if is_multiplayer_game and pid != local_player_id:
		return
	var player := _get_player_state(pid)
	var cards: Array[Dictionary] = player.monster_deck.duplicate(true)
	monster_deck_view_overlay.show_cards(cards, tr("STR_GB_MONSTER_DECK_TITLE_FMT") % cards.size())


# --- Monster rank-up selection UI ---

func _play_action_required_if_not_turn_player(player_id: int) -> void:
	if turn_manager and player_id != turn_manager.game_state.current_player_id:
		SfxManager.play("action_required")


## Router handler for monster rank-up: board-side button state wraps the
## viewer's mandatory selection mode.
func _show_monster_rankup(monsters: Array, valid_indices: Array[int], prompt: String, resolve_cb: Callable) -> void:
	_disable_all_buttons()
	monster_deck_view_overlay.show_rankup(monsters, valid_indices, prompt, func(index: int) -> void:
		btn_confirm.disabled = true
		resolve_cb.call(index))


# --- Zone stack view UI ---

func _stack_view_header(single_key: String, under_key: String, n: int, total: int) -> String:
	## Build a stack view title. When the stack has cards under the top card,
	## use the "{U} Under" variant so the top-vs-under split is explicit.
	if total > 1:
		return tr(under_key) \
			.replace("{N}", str(n)) \
			.replace("{C}", str(total)) \
			.replace("{U}", str(total - 1))
	return tr(single_key).replace("{N}", str(n)).replace("{C}", str(total))


func _on_zone_slot_clicked(zone_num: int, pid: int) -> void:
	if waiting_for_card_select or waiting_for_zone_select or _zone_target_selecting:
		return
	var player := _get_player_state(pid)
	var zone_idx: int = zone_num - 1
	if zone_idx < 0 or zone_idx >= 8:
		return
	var stack: Array = player.get_zone_stack(zone_idx)
	# Include the monster card if this is the monster's zone
	var has_monster: bool = not player.current_monster.is_empty() and (player.monster_zone - 1) == zone_idx
	if stack.is_empty() and not has_monster:
		return
	var cards: Array[Dictionary] = []
	if has_monster:
		cards.append(player.current_monster)
		for m in player.monster_stack:
			cards.append(m)
	for card_data in stack:
		cards.append(card_data)
	zone_stack_view_overlay.show_cards(cards, _stack_view_header(
		"STR_GB_ZONE_HEADER_FMT", "STR_GB_ZONE_HEADER_UNDER_FMT", zone_num, cards.size()))


# --- Card zoom (right-click) UI ---

func _on_zone_slot_right_clicked(zone_num: int, pid: int) -> void:
	var player := _get_player_state(pid)
	var zone_idx: int = zone_num - 1
	if zone_idx < 0 or zone_idx >= 8:
		return
	# Show the monster card if this is the monster's zone, otherwise the top battle card
	var card_data: Dictionary = {}
	var zoom_ctx: Dictionary = {}
	if not player.current_monster.is_empty() and (player.monster_zone - 1) == zone_idx:
		card_data = player.current_monster
		zoom_ctx = {"player_id": pid, "location": "monster"}
	elif player.zone_has_cards(zone_idx):
		card_data = player.get_zone_top_card(zone_idx)
		zoom_ctx = {"player_id": pid, "location": "zone", "index": zone_idx}
	if card_data.is_empty():
		return
	_show_card_zoom(card_data, 0, zoom_ctx)


func _on_strategy_slot_right_clicked(strategy_idx: int, pid: int) -> void:
	var player := _get_player_state(pid)
	if strategy_idx < 0 or strategy_idx >= player.strategy_zones.size():
		return
	var card_data: Dictionary = player.strategy_zones[strategy_idx]
	if card_data.is_empty():
		return
	_show_card_zoom(card_data, 0, {"player_id": pid, "location": "strategy", "index": strategy_idx})


func _on_strategy_slot_clicked(strategy_idx: int, pid: int) -> void:
	if waiting_for_card_select or waiting_for_zone_select or _zone_target_selecting or _strategy_target_selecting:
		return
	var player := _get_player_state(pid)
	if strategy_idx < 0 or strategy_idx >= player.strategy_zones.size():
		return
	var card_data: Dictionary = player.strategy_zones[strategy_idx]
	if card_data.is_empty():
		return
	var stack: Array = []
	if strategy_idx < player.strategy_zone_stacks.size():
		stack = player.strategy_zone_stacks[strategy_idx]
	var cards: Array[Dictionary] = [card_data]
	for c in stack:
		cards.append(c)
	zone_stack_view_overlay.show_cards(cards, _stack_view_header(
		"STR_GB_STRATEGY_HEADER_FMT", "STR_GB_STRATEGY_HEADER_UNDER_FMT", strategy_idx + 1, cards.size()))


func _on_card_long_press_zoom(card: Control) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		var mod: int = card.get_play_cost_modifier() if card.has_method("get_play_cost_modifier") else 0
		_show_card_zoom(card.card_data, mod)


func _on_hand_card_right_clicked(card: Control, hand_player_id: int) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		var mod: int = card.get_play_cost_modifier() if card.has_method("get_play_cost_modifier") else 0
		_show_card_zoom(card.card_data, mod, _hand_zoom_ctx(card.card_data, hand_player_id))


## Zoom shim — display lives on CardZoomOverlayUI (router hook + several
## long-press/right-click callers). Callers with board context pass zoom_ctx
## ({player_id, location: "zone"|"monster"|"strategy"|"hand", index}); the
## rest fall back to locating the exact copy by its per-copy instance id.
func _show_card_zoom(card_data: Dictionary, play_cost_modifier: int = 0, zoom_ctx: Dictionary = {}) -> void:
	if zoom_ctx.is_empty():
		zoom_ctx = _infer_zoom_ctx(card_data)
	card_zoom_overlay.show_card(card_data, play_cost_modifier, _zoom_entries_for(zoom_ctx))


## PlayerState for zoom lookups that must not assume either mode is ready
## (returns null instead of indexing an unpopulated client cache).
func _zoom_player_state(pid: int) -> PlayerState:
	if pid < 0 or pid > 1:
		return null
	if turn_manager and turn_manager.game_state:
		return turn_manager.game_state.players[pid]
	if pid < _client_players.size():
		return _client_players[pid]
	return null


func _hand_zoom_ctx(card_data: Dictionary, hand_player_id: int) -> Dictionary:
	var player := _zoom_player_state(hand_player_id)
	if player == null:
		return {}
	var card_id: String = card_data.get("id", "")
	for hi in range(player.hand.size()):
		if player.hand[hi].get("id", "") == card_id:
			return {"player_id": hand_player_id, "location": "hand", "index": hi}
	return {}


## Locate the zoomed copy for context-free callers (overlay grids, gallery,
## long-press). In-play locations are searched before hands: monster ids are
## bare template ids, so an in-play hit must win over a same-template hand
## copy. A miss means no modifiers apply to this exact copy (deck/discard/
## gallery duplicates) and the sources panel stays hidden.
func _infer_zoom_ctx(card_data: Dictionary) -> Dictionary:
	var card_id: String = card_data.get("id", "")
	if card_id.is_empty():
		return {}
	for pid in range(2):
		var player := _zoom_player_state(pid)
		if player == null:
			continue
		if player.current_monster.get("id", "") == card_id:
			return {"player_id": pid, "location": "monster"}
		for i in range(8):
			if player.get_zone_top_card(i).get("id", "") == card_id:
				return {"player_id": pid, "location": "zone", "index": i}
		for si in range(player.strategy_zones.size()):
			if player.strategy_zones[si].get("id", "") == card_id:
				return {"player_id": pid, "location": "strategy", "index": si}
	for pid in range(2):
		var player := _zoom_player_state(pid)
		if player == null:
			continue
		for hi in range(player.hand.size()):
			if player.hand[hi].get("id", "") == card_id:
				return {"player_id": pid, "location": "hand", "index": hi}
	return {}


## Resolve a zoom context to modifier-source entries. Host/solo builds them
## on demand from the effect handler; clients read the breakdowns packed
## into the state broadcast (mirrors the threat_display host/client split).
func _zoom_entries_for(zoom_ctx: Dictionary) -> Array:
	if zoom_ctx.is_empty():
		return []
	var pid: int = zoom_ctx.get("player_id", -1)
	var location: String = zoom_ctx.get("location", "")
	var index: int = zoom_ctx.get("index", -1)
	if turn_manager and turn_manager.effect_handler:
		return _host_zoom_entries(pid, location, index)
	return ModifierBreakdown.collect(_session.client_modifier_breakdowns, pid, location, index)


func _host_zoom_entries(pid: int, location: String, index: int) -> Array:
	var eh: EffectHandler = turn_manager.effect_handler
	var player: PlayerState = turn_manager.game_state.players[pid]
	var out: Array = []
	match location:
		"zone":
			if index >= 0 and index < 8:
				out.append_array(eh.get_zone_cp_breakdown(pid)[index])
				out.append_array(eh.get_field_rank_breakdown(pid)[index])
		"monster":
			ModifierBreakdown.append(out, "cp", eh.get_monster_cp_modifier(pid), player.current_monster)
			out.append_array(eh.get_threat_level_breakdown(pid))
		"strategy":
			var mods: Array = eh.get_strategy_cp_modifiers(pid)
			if index >= 0 and index < mods.size() and index < player.strategy_zones.size():
				ModifierBreakdown.append(out, "cp", int(mods[index]), player.strategy_zones[index])
		"hand":
			if index >= 0 and index < player.hand.size():
				out = ModifierBreakdown.hand_entries(eh, pid, player.hand[index])
	return out


## Overlay on_hidden hook: reset all slot input state so no timers or
## pending clicks carry over.
func _on_card_zoom_hidden() -> void:
	for board in [player1_board, player2_board]:
		for slot in board.zone_slots:
			slot.reset_input_state()

# --- Card hover preview ---

func _show_card_preview(data: Dictionary, play_cost_modifier: int = 0) -> void:
	if _is_mobile_layout:
		return # Mobile uses tap-to-zoom instead of hover preview
	if data.is_empty():
		return
	_preview_card.set_card_data_dict(data)
	if _preview_card.has_method("set_play_cost_modifier"):
		_preview_card.set_play_cost_modifier(play_cost_modifier)
	var is_strategy: bool = data.get("card_type", -1) == CardEnums.CardType.STRATEGY
	if is_strategy:
		_show_strategy_preview()
	else:
		_show_normal_preview()
	# Re-orient the badge after preview rotation/size was applied above.
	if _preview_card.has_method("update_play_cost_badge_layout"):
		_preview_card.update_play_cost_badge_layout()


func _show_normal_preview() -> void:
	# Position container at top-right for normal cards
	_preview_container.anchor_left = 0.75
	_preview_container.anchor_right = 0.995
	_preview_container.anchor_top = 0.05
	_preview_container.anchor_bottom = 0.75
	# Fit card (5:7 aspect) inside container while preserving ratio
	var container_size := _preview_container.size
	var card_ratio := 5.0 / 7.0
	var card_w := container_size.x
	var card_h := card_w / card_ratio
	if card_h > container_size.y:
		card_h = container_size.y
		card_w = card_h * card_ratio
	var card_pos := Vector2((container_size.x - card_w) / 2.0, (container_size.y - card_h) / 2.0)
	var padding := 6.0
	_preview_bg.position = card_pos - Vector2(padding, padding)
	_preview_bg.size = Vector2(card_w, card_h) + Vector2(padding * 2, padding * 2)
	_preview_card.size = Vector2(card_w, card_h)
	_preview_card.position = card_pos
	_preview_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_preview_card.scale = Vector2.ONE
	_preview_card.rotation = 0.0
	_preview_container.visible = true


func _show_strategy_preview() -> void:
	# Position container at right edge, between opponent board and player hand
	_preview_container.anchor_left = 0.6
	_preview_container.anchor_right = 1.0
	_preview_container.anchor_top = 0.47
	_preview_container.anchor_bottom = 0.88
	var container_size := _preview_container.size
	var card_ratio := 5.0 / 7.0
	# When rotated 90 CCW, visual width = card_h and visual height = card_w
	# Fit so the rotated card fills the container
	var visual_h := container_size.y
	var card_w := visual_h # un-rotated height becomes visual height
	var card_h := card_w / card_ratio # un-rotated width becomes visual width
	if card_h > container_size.x:
		card_h = container_size.x
		card_w = card_h * card_ratio
		visual_h = card_w
	var visual_w := card_h
	var card_pos := Vector2(
		container_size.x - visual_w,
		(container_size.y - visual_h) / 2.0
	)
	_preview_card.size = Vector2(card_w, card_h)
	_preview_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_preview_card.rotation = - PI / 2.0
	_preview_card.scale = Vector2.ONE
	_preview_card.position = card_pos + Vector2((visual_w - card_w) / 2.0, (visual_h - card_h) / 2.0)
	var padding := 6.0
	_preview_bg.position = card_pos - Vector2(padding, padding)
	_preview_bg.size = Vector2(visual_w, visual_h) + Vector2(padding * 2, padding * 2)
	_preview_container.visible = true


func _hide_card_preview() -> void:
	_preview_container.visible = false


func _on_log_meta_hover_started(meta: Variant) -> void:
	var card_id: String = str(meta)
	var data: Dictionary = CardData.get_card_by_id(card_id)
	if not data.is_empty():
		_show_card_preview(data)


func _on_log_meta_hover_ended(_meta: Variant) -> void:
	_hide_card_preview()


func _on_log_meta_clicked(meta: Variant) -> void:
	var m: String = str(meta)
	if m.begins_with("reshuffle:"):
		_hide_card_preview()
		_show_reshuffle_snapshot(m.substr("reshuffle:".length()))


func _show_reshuffle_snapshot(ids_csv: String) -> void:
	## Reuse the discard-view overlay to show a read-only snapshot of the cards that
	## were shuffled from the discard pile back into the deck. ids_csv is the
	## comma-joined base card ids encoded in the log line's meta.
	var cards: Array[Dictionary] = []
	for id in ids_csv.split(",", false):
		var data: Dictionary = CardData.get_card_by_id(id)
		if not data.is_empty():
			cards.append(data.duplicate(true))
	discard_view_overlay.show_cards(cards, tr("STR_GB_RESHUFFLE_SNAPSHOT_TITLE_FMT") % cards.size())


func _set_mouse_filter_ignore_recursive(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_set_mouse_filter_ignore_recursive(child)


# --- Card grid helpers ---

func _set_gallery_hover(card: Control) -> void:
	card.hover_scale = 1.05
	card.hover_lift = 0.0
	card.gui_input.connect(_on_gallery_card_input.bind(card))


func _on_gallery_card_input(event: InputEvent, card: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if "card_data" in card and not card.card_data.is_empty():
			_show_card_zoom(card.card_data)
	elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		# Only treat as double-click if the same card instance was clicked both times.
		# _last_clicked_card is a static var set in card._gui_input (which runs AFTER
		# this signal handler), so it holds the card from the PREVIOUS click.
		var last_card = card._last_clicked_card
		if is_instance_valid(last_card) and last_card == card:
			if "card_data" in card and not card.card_data.is_empty():
				_show_card_zoom(card.card_data)


func _get_card_template_id(card_data: Dictionary) -> String:
	## Extract the template card number from an instance ID.
	## Instance IDs: "EBP01-001_1_0" -> "EBP01-001", Monster IDs: "EBP01-001" -> "EBP01-001"
	var id: String = card_data.get("id", "")
	var parts := id.split("_")
	return parts[0] if not parts.is_empty() else id


func _group_cards(cards: Array[Dictionary], matching_ids: Dictionary = {}) -> Array[Dictionary]:
	## Group cards by template ID. Returns Array of {card_data, count, has_match}.
	var groups: Dictionary = {} # template_id -> {card_data, count, has_match}
	var order: Array[String] = [] # Preserve first-seen order
	for card_data in cards:
		var tid := _get_card_template_id(card_data)
		if groups.has(tid):
			groups[tid]["count"] += 1
			if matching_ids.has(card_data.get("id", "")):
				groups[tid]["has_match"] = true
		else:
			groups[tid] = {
				"card_data": card_data,
				"count": 1,
				"has_match": matching_ids.has(card_data.get("id", "")),
			}
			order.append(tid)

	var result: Array[Dictionary] = []
	for tid in order:
		result.append(groups[tid])
	return result


func _add_count_badge(card: Control, count: int) -> void:
	if count <= 1:
		return
	var badge := Label.new()
	badge.text = "x%d" % count
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color.YELLOW)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -40
	badge.offset_right = -4
	badge.offset_top = 10
	card.add_child(badge)


func _clear_grid(grid: GridContainer, click_handler: Callable) -> void:
	for child in grid.get_children():
		if "card_clicked" in child and child.card_clicked.is_connected(click_handler):
			child.card_clicked.disconnect(click_handler)
		child.queue_free()


# --- Multiplayer: State broadcast (host -> client) ---

## Sync shims — state broadcast machinery lives on MultiplayerSync.
## Kept under the old names because dozens of handlers call them (and
## _on_state_changed connects per-PlayerState signals to this path).
func _broadcast_state() -> void:
	_sync.broadcast_state()


func _flush_broadcast() -> void:
	_sync.flush_broadcast()


# --- Hooks called by MultiplayerSync while applying received state ---

## Append a broadcast log entry (token Dictionary or legacy String) to the
## local log view.
func _append_log_entry(entry) -> void:
	_log_chat.append_remote_entry(entry)


## Apply monster color gradients from the client-side state cache (first
## state receive on the client).
func _apply_client_monster_gradients() -> void:
	for i in range(2):
		var board = player1_board if i == 0 else player2_board
		if not _client_players[i].current_monster.is_empty():
			board.apply_monster_gradient(_client_players[i].current_monster)


## Sync player names from host (disambiguate from client's perspective).
func _apply_remote_player_names(host_names: Array) -> void:
	if host_names.size() != 2:
		return
	var canonical: Array[String] = []
	for i in range(2):
		canonical.append(str(host_names[i]))
	GameLog.player_names = GameLog.disambiguate(canonical, local_player_id)
	for i in range(2):
		if i < _turn_tracker_headers.size():
			_turn_tracker_headers[i].text = GameLog.player_name(i)


## Host -> Client: valid actions and playable indices
func _rpc_receive_action_context(actions_json: String, playable_json: String) -> void:
	RpcLogger.log_receive("receive_action_context", actions_json.length() + playable_json.length())
	_action_pending = false
	# Clean up any stale discard/selection state before enabling action buttons
	if _discard_selecting:
		_force_cleanup_discard_selection()
	_clear_card_highlight()
	_cancel_selection()

	var actions: Array = JSON.parse_string(actions_json)
	_client_playable = JSON.parse_string(playable_json)
	# Store valid_actions in playable for _on_cancel_pressed path
	_client_playable["valid_actions"] = actions
	# Convert float arrays to int arrays
	for key in _client_playable:
		if _client_playable[key] is Array:
			var arr: Array = _client_playable[key]
			for j in range(arr.size()):
				if arr[j] is float:
					arr[j] = int(arr[j])
	_update_action_buttons(actions)


## Host -> Client: log message (legacy raw-string path; kept for compatibility)
func _rpc_receive_log(text: String) -> void:
	_log_chat.receive_log(text)


## Any peer -> Any peer: chat message
func _rpc_receive_chat(sender_player_id: int, text: String) -> void:
	_log_chat.receive_chat(sender_player_id, text)


## Host -> Client: deck search request (player must choose a card)
func _rpc_deck_search_requested(matching_json: String, all_json: String, prompt: String, allow_skip: bool = true) -> void:
	RpcLogger.log_receive("deck_search_requested", matching_json.length() + all_json.length() + prompt.length())
	var matching_ids: Array = JSON.parse_string(matching_json)
	var all_ids: Array = JSON.parse_string(all_json)
	_router.show_deck_search(StateCodec.ids_to_cards(matching_ids), StateCodec.ids_to_cards(all_ids), prompt, allow_skip)


## Host -> Client: deck arrange request (player must reorder/discard cards)
func _rpc_deck_arrange_requested(cards_json: String, prompt: String) -> void:
	RpcLogger.log_receive("deck_arrange_requested", cards_json.length() + prompt.length())
	var ids: Array = JSON.parse_string(cards_json)
	_router.show_deck_arrange(StateCodec.ids_to_cards(ids), prompt)


## Host -> Client: card select request
func _rpc_card_select_requested(matching_json: String, all_json: String, prompt: String, min_count: int, max_count: int) -> void:
	RpcLogger.log_receive("card_select_requested", matching_json.length() + all_json.length() + prompt.length())
	var matching_ids: Array = JSON.parse_string(matching_json)
	var all_ids: Array = JSON.parse_string(all_json)
	_router.show_card_select(StateCodec.ids_to_cards(matching_ids), StateCodec.ids_to_cards(all_ids), prompt, min_count, max_count)


## Host -> Client: hand card selection request (player must choose a card from hand)
func _rpc_hand_card_selection_requested(indices_json: String, prompt: String, allow_skip: bool, source_id: String = "") -> void:
	RpcLogger.log_receive("hand_card_selection_requested", indices_json.length() + prompt.length() + 1)
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(indices_json)
	var valid_indices: Array[int] = []
	for v in parsed:
		valid_indices.append(int(v))
	if _client_current_player_id != local_player_id:
		SfxManager.play("action_required")
	_selection._show_hand_card_selection(local_player_id, valid_indices, prompt, allow_skip, source_id)


## Host -> Client: confirmation request (draw / next turn)
func _rpc_confirmation_requested(prompt: String, setting: String) -> void:
	RpcLogger.log_receive("confirmation_requested", prompt.length() + setting.length())
	if NetworkManager.is_host():
		return
	if _player_settings[local_player_id].get(setting, false):
		RpcLogger.log_send("confirmation_resolved", 0)
		_sync._rpc_confirmation_resolved.rpc_id(NetworkManager.host_peer_id)
		return
	_show_confirmation(prompt)


## Host UI refresh after a remote player's name landed in game_state
## (called from MultiplayerSync._rpc_send_player_name).
func _on_player_names_updated() -> void:
	GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)
	# Update host UI (disambiguation may affect both labels)
	for i in range(2):
		if i < _turn_tracker_headers.size():
			_turn_tracker_headers[i].text = GameLog.player_name(i)


## Host -> Client: hand discard request (player must choose cards to discard)
func _rpc_hand_discard_requested(discard_count: int, source_id: String = "") -> void:
	RpcLogger.log_receive("hand_discard_requested", 4)
	if NetworkManager.is_host():
		return # Safety: this RPC is only for clients
	if _client_current_player_id != local_player_id:
		SfxManager.play("action_required")
	_selection._show_hand_discard_selection(local_player_id, discard_count, source_id)


## Host -> Client: zone target request (player must choose a zone)
func _rpc_zone_target_requested(target_player_id: int, zones_json: String, prompt: String, allow_skip: bool, card_id: String = "", source_id: String = "") -> void:
	RpcLogger.log_receive("zone_target_requested", 4 + zones_json.length() + prompt.length() + 1)
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(zones_json)
	var valid_zones: Array[int] = []
	for v in parsed:
		valid_zones.append(int(v))
	_selection._show_zone_target_selection(local_player_id, target_player_id, valid_zones, prompt, allow_skip, card_id, source_id)


## Host -> Client: strategy target request (player must choose a strategy zone)
func _rpc_strategy_target_requested(target_player_id: int, indices_json: String, prompt: String, source_id: String = "") -> void:
	RpcLogger.log_receive("strategy_target_requested", 4 + indices_json.length() + prompt.length())
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(indices_json)
	var valid_indices: Array[int] = []
	for v in parsed:
		valid_indices.append(int(v))
	_selection._show_strategy_target_selection(local_player_id, target_player_id, valid_indices, prompt, source_id)


## Host -> Client: choice request (player must choose ability order)
func _rpc_choice_requested(options_json: String, prompt: String, card_ids_json: String = "[]", source_refs_json: String = "[]") -> void:
	RpcLogger.log_receive("choice_requested", options_json.length() + prompt.length())
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(options_json)
	var options: Array[String] = []
	for v in parsed:
		options.append(str(v))
	var parsed_ids = JSON.parse_string(card_ids_json)
	var card_ids: Array[String] = []
	if parsed_ids is Array:
		for v in parsed_ids:
			card_ids.append(str(v))
	var parsed_refs = JSON.parse_string(source_refs_json)
	var source_refs: Array = []
	if parsed_refs is Array:
		for v in parsed_refs:
			# JSON turns ints into floats — re-coerce the numeric fields.
			var ref: Dictionary = v if v is Dictionary else {}
			if not ref.is_empty():
				ref["player_id"] = int(ref.get("player_id", -1))
				ref["index"] = int(ref.get("index", -1))
			source_refs.append(ref)
	_selection._show_choice_selection(local_player_id, options, prompt, card_ids, source_refs)


## Host -> Client: prompt monster rank-up selection
func _rpc_monster_rankup_requested(monsters_json: String, indices_json: String, prompt: String) -> void:
	RpcLogger.log_receive("monster_rankup_requested", monsters_json.length() + indices_json.length() + prompt.length())
	if NetworkManager.is_host():
		return
	var monster_ids: Array = JSON.parse_string(monsters_json)
	var parsed_indices: Array = JSON.parse_string(indices_json)
	SfxManager.play("action_required")
	_router.show_monster_rankup(StateCodec.ids_to_cards(monster_ids), parsed_indices, prompt)


## Server -> Client (dedicated only): display-only cards-revealed overlay
## (the server already resolved the effect; dismissing changes nothing).
func _rpc_cards_revealed_shown(cards_json: String, title: String) -> void:
	if NetworkManager.is_host():
		return
	var ids: Variant = JSON.parse_string(cards_json)
	if not ids is Array or ids.is_empty():
		return
	zone_stack_view_overlay.show_revealed(StateCodec.ids_to_cards(ids), _resolve_translated_text(title), Callable())


## Host -> Client: highlight a zone card during effect resolution
func _rpc_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	RpcLogger.log_receive("effect_zone_highlighted", 8)
	if NetworkManager.is_host():
		return
	_apply_zone_highlight(pid, zone_index, true)


## Host -> Client: unhighlight a zone card after effect resolution
func _rpc_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	RpcLogger.log_receive("effect_zone_unhighlighted", 8)
	if NetworkManager.is_host():
		return
	_apply_zone_highlight(pid, zone_index, false)


## Host -> Client: highlight the source card of an active effect
func _rpc_effect_card_highlighted(pid: int, card_id: String) -> void:
	RpcLogger.log_receive("effect_card_highlighted", 4 + card_id.length())
	if NetworkManager.is_host():
		return
	_apply_card_highlight(pid, card_id, true)


## Host -> Client: unhighlight the source card after effect resolves
func _rpc_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	RpcLogger.log_receive("effect_card_unhighlighted", 4 + card_id.length())
	if NetworkManager.is_host():
		return
	_apply_card_highlight(pid, card_id, false)


## Host/Server -> Client: pending standby-effect stack snapshot
func _rpc_effect_stack_changed(stack_json: String) -> void:
	RpcLogger.log_receive("effect_stack_changed", stack_json.length())
	if NetworkManager.is_host():
		return
	var parsed = JSON.parse_string(stack_json)
	var rows: Array = []
	if parsed is Array:
		for v in parsed:
			var row: Dictionary = v if v is Dictionary else {}
			if row.is_empty():
				continue
			# JSON turns ints into floats — re-coerce the numeric fields.
			row["player_id"] = int(row.get("player_id", -1))
			var loc = row.get("location", {})
			if loc is Dictionary and not loc.is_empty():
				loc["player_id"] = int(loc.get("player_id", -1))
				loc["index"] = int(loc.get("index", -1))
			rows.append(row)
	if _effect_stack:
		_effect_stack.show_stack(rows)


## Host -> Client: game over
func _rpc_receive_game_ended(winner_id: int, reason_key: String) -> void:
	_end_game.rpc_receive_game_ended(winner_id, reason_key)


func _rpc_receive_replay(compressed: PackedByteArray) -> void:
	_end_game.rpc_receive_replay(compressed)


# --- Multiplayer: State deserialization (client) ---

# --- Stats upload ---

func _upload_stats(winner_id: int, reason: String, is_disconnect: bool) -> void:
	_end_game.upload_stats(winner_id, reason, is_disconnect)


# --- Multiplayer: Disconnect handling ---

# --- Play vs Bot While Waiting (lobby-bot mode) ---

func _setup_lobby_bot_ui() -> void:
	_lobby_banner_start_msec = Time.get_ticks_msec()
	# Park the banner under the chat row inside the log panel so cards/board
	# elements never cover it.
	var log_vbox: VBoxContainer = $LogPanel/LogVBox
	var hbox := HBoxContainer.new()
	hbox.name = "LobbyWaitingBanner"
	hbox.add_theme_constant_override("separation", 8)

	_lobby_banner_label = Label.new()
	_lobby_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lobby_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_banner_label.add_theme_font_size_override("font_size", 11)
	_lobby_banner_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3, 1))
	hbox.add_child(_lobby_banner_label)

	var return_btn := Button.new()
	return_btn.text = tr("STR_GB_RETURN_TO_LOBBY")
	return_btn.add_theme_font_size_override("font_size", 10)
	return_btn.pressed.connect(_on_lobby_banner_return_pressed)
	hbox.add_child(return_btn)

	log_vbox.add_child(hbox)
	_lobby_banner = hbox
	_update_lobby_banner_label()

	NetworkManager.player_connected.connect(_on_lobby_opponent_connected)
	NetworkManager.player_disconnected.connect(_on_lobby_opponent_disconnected)
	tree_exiting.connect(_disconnect_lobby_bot_signals)


func _disconnect_lobby_bot_signals() -> void:
	if NetworkManager.player_connected.is_connected(_on_lobby_opponent_connected):
		NetworkManager.player_connected.disconnect(_on_lobby_opponent_connected)
	if NetworkManager.player_disconnected.is_connected(_on_lobby_opponent_disconnected):
		NetworkManager.player_disconnected.disconnect(_on_lobby_opponent_disconnected)


func _on_lobby_opponent_disconnected(_peer_id: int) -> void:
	# Opponent gave up while we kept playing bot. Reset so a future joiner re-triggers the dialog.
	_opponent_found_handled = false
	_cleanup_opponent_found_dialog()


func _process_lobby_banner_tick() -> void:
	if _is_lobby_bot and is_instance_valid(_lobby_banner_label):
		_update_lobby_banner_label()


func _update_lobby_banner_label() -> void:
	var elapsed: int = int((Time.get_ticks_msec() - _lobby_banner_start_msec) / 1000.0)
	_lobby_banner_label.text = tr("STR_GB_LOBBY_WAITING_BANNER_FMT") % [int(elapsed / 60.0), elapsed % 60]


func _on_lobby_banner_return_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.exit_lobby_bot_game()
	NetworkManager.change_scene("res://scenes/ui/PublicLobby.tscn")


func _on_lobby_opponent_connected(_peer_id: int) -> void:
	if not _is_lobby_bot or _opponent_found_handled:
		return
	_opponent_found_handled = true
	_show_opponent_found_dialog()


func _show_opponent_found_dialog() -> void:
	SfxManager.play("action_required")
	_opponent_found_dialog = AcceptDialog.new()
	_opponent_found_dialog.title = tr("STR_GB_OPPONENT_FOUND_TITLE")
	_opponent_found_dialog.dialog_text = tr("STR_GB_OPPONENT_FOUND_BODY")
	_opponent_found_dialog.get_ok_button().text = tr("STR_GB_OPPONENT_FOUND_START")
	_opponent_found_dialog.add_button(tr("STR_GB_OPPONENT_FOUND_KEEP_BOT"), false, "keep_bot")
	_opponent_found_dialog.confirmed.connect(_on_opponent_found_start)
	_opponent_found_dialog.custom_action.connect(_on_opponent_found_custom_action)
	add_child(_opponent_found_dialog)
	_opponent_found_dialog.popup_centered()

	_opponent_found_remaining = 20
	_opponent_found_timer = Timer.new()
	_opponent_found_timer.wait_time = 1.0
	_opponent_found_timer.one_shot = false
	_opponent_found_timer.timeout.connect(_on_opponent_found_timer_tick)
	add_child(_opponent_found_timer)
	_opponent_found_timer.start()
	_update_opponent_found_countdown()


func _on_opponent_found_timer_tick() -> void:
	_opponent_found_remaining -= 1
	if _opponent_found_remaining <= 0:
		_on_opponent_found_start()
		return
	_update_opponent_found_countdown()


func _update_opponent_found_countdown() -> void:
	if not is_instance_valid(_opponent_found_dialog):
		return
	_opponent_found_dialog.dialog_text = "%s\n\n%s" % [
		tr("STR_GB_OPPONENT_FOUND_BODY"),
		tr("STR_GB_OPPONENT_FOUND_AUTO_FMT") % _opponent_found_remaining,
	]


func _on_opponent_found_start() -> void:
	_cleanup_opponent_found_dialog()
	NetworkManager.exit_lobby_bot_game()
	NetworkManager.change_scene("res://scenes/ui/PublicLobby.tscn")


func _on_opponent_found_custom_action(action: StringName) -> void:
	if action == "keep_bot":
		_cleanup_opponent_found_dialog()
		# Tell the joined client we're declining so they can drop and find another lobby
		# rather than sitting indefinitely on a "Waiting for game to start" screen.
		NetworkManager.notify_match_declined()


func _cleanup_opponent_found_dialog() -> void:
	if is_instance_valid(_opponent_found_timer):
		_opponent_found_timer.stop()
		_opponent_found_timer.queue_free()
		_opponent_found_timer = null
	if is_instance_valid(_opponent_found_dialog):
		_opponent_found_dialog.queue_free()
		_opponent_found_dialog = null


# --- In-flight action indicator (multiplayer client) ---

func _setup_pending_indicator() -> void:
	_pending_indicator = Panel.new()
	_pending_indicator.name = "PendingIndicator"
	_pending_indicator.mouse_filter = Control.MOUSE_FILTER_STOP
	_pending_indicator.visible = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.03, 0.02, 0.85)
	bg.set_corner_radius_all(4)
	_pending_indicator.add_theme_stylebox_override("panel", bg)

	_pending_indicator_label = Label.new()
	_pending_indicator_label.anchor_right = 1.0
	_pending_indicator_label.anchor_bottom = 1.0
	_pending_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pending_indicator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pending_indicator_label.text = tr("STR_GB_ACTION_SENDING")
	_pending_indicator_label.add_theme_font_size_override("font_size", 16)
	_pending_indicator_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3, 1))
	_pending_indicator.add_child(_pending_indicator_label)

	# Sibling overlay, not a VBox child: adding it inside ActionPanel would give
	# it its own layout row and bounce the button rows every time it toggles.
	add_child(_pending_indicator)


func _process_pending_indicator() -> void:
	if not _pending_indicator:
		return
	# Show only when the dedicated server looks unresponsive: we submitted an
	# action and NOTHING (state, prompts, even keepalives) has arrived since.
	# Any inbound packet bumps last_received_ms and hides the indicator.
	var stalled := false
	if _action_pending and action_panel.visible and NetworkManager.server_peer:
		var silent_ms := Time.get_ticks_msec() - _action_submitted_ms
		stalled = silent_ms >= PENDING_INDICATOR_STALL_MS \
			and NetworkManager.server_peer.last_received_ms < _action_submitted_ms
	_pending_indicator.visible = stalled
	if stalled:
		_pending_indicator.global_position = action_panel.global_position
		_pending_indicator.size = action_panel.size
