extends Control

## Main game controller. Orchestrates the UI, TurnManager, and both PlayerBoards.
## In multiplayer, the host runs TurnManager and broadcasts state to the client.
## The client receives state via RPC and sends actions back to the host.

var turn_manager: TurnManager # Only exists on host/solo
var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# Multiplayer state
var is_multiplayer_game: bool = false
var local_player_id: int = 0 # 0 for host/solo, 1 for client

# Client-side state (populated from host RPCs)
var _client_players: Array[PlayerState] = []
var _client_current_player_id: int = 0
var _client_playable: Dictionary = {} # Playable card/zone indices from host
var _client_cp_modifiers: Array = [0, 0]
var _client_threat_modifiers: Array = [0, 0]
var _client_zone_cp_mods: Array = [[], []]

# UI references
@onready var player1_board: Control = $VBoxContainer/BoardArea/BoardColumn/Player1Board
@onready var player2_board: Control = $VBoxContainer/BoardArea/BoardColumn/Player2Board
@onready var action_panel: Control = $VBoxContainer/BottomHUD/ActionPanel
@onready var phase_label: Label = $VBoxContainer/TopHUD/PhaseLabel
@onready var turn_label: Label = $VBoxContainer/TopHUD/TurnLabel
@onready var log_output: RichTextLabel = $LogPanel/LogOutput
@onready var end_game_panel: Control = $EndGamePanel
@onready var card_select_prompt: Label = $VBoxContainer/TopHUD/CardSelectPromptTop

# Hand references
@onready var player1_hand: Node2D = $Player1Hand
@onready var player2_hand: Node2D = $Player2Hand
@onready var player1_hand_space: Control = $VBoxContainer/BoardArea/BoardColumn/Player1HandSpace
@onready var player2_hand_space: Control = $VBoxContainer/BoardArea/BoardColumn/Player2HandSpace

# Action buttons
@onready var btn_play_battle: Button = $VBoxContainer/BottomHUD/ActionPanel/Row1/PlayBattle
@onready var btn_play_strategy: Button = $VBoxContainer/BottomHUD/ActionPanel/Row1/PlayStrategy
@onready var btn_gain_rage: Button = $VBoxContainer/BottomHUD/ActionPanel/Row1/GainRage
@onready var btn_play_monster: Button = $VBoxContainer/BottomHUD/ActionPanel/Row2/PlayMonster
@onready var btn_invade: Button = $VBoxContainer/BottomHUD/ActionPanel/Row2/Invade
@onready var btn_pass: Button = $VBoxContainer/BottomHUD/ActionPanel/Row2/Pass

# Deck search UI references
@onready var deck_search_overlay: Control = $DeckSearchOverlay
@onready var deck_search_prompt: Label = $DeckSearchOverlay/DeckSearchPanel/VBox/PromptLabel
@onready var deck_search_grid: GridContainer = $DeckSearchOverlay/DeckSearchPanel/VBox/ScrollContainer/CardGrid
@onready var deck_search_skip: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/SkipButton
@onready var deck_search_show_all: CheckButton = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/ShowAllToggle
@onready var deck_search_stacked: CheckButton = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/StackedToggle
@onready var deck_search_view_board: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/ViewBoardButton
@onready var show_cards_button: Button = $ShowCardsButton

# Discard view UI references
@onready var discard_view_overlay: Control = $DiscardViewOverlay
@onready var discard_view_title: Label = $DiscardViewOverlay/DiscardViewPanel/VBox/TitleLabel
@onready var discard_view_grid: GridContainer = $DiscardViewOverlay/DiscardViewPanel/VBox/ScrollContainer/CardGrid
@onready var discard_view_close: Button = $DiscardViewOverlay/DiscardViewPanel/VBox/CloseButton
@onready var discard_view_stacked: CheckButton = $DiscardViewOverlay/DiscardViewPanel/VBox/StackedToggle

# Stored deck search data for toggling between matching/all/stacked
var _deck_search_matching: Array[Dictionary] = []
var _deck_search_all: Array[Dictionary] = []
var _deck_search_matching_ids: Dictionary = {} # card id -> true, for highlighting

# Stored discard view data for stacked toggle
var _discard_view_cards: Array[Dictionary] = []

# Monster deck view UI references
@onready var monster_deck_view_overlay: Control = $MonsterDeckViewOverlay
@onready var monster_deck_view_title: Label = $MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/TitleLabel
@onready var monster_deck_view_grid: GridContainer = $MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/ScrollContainer/CardGrid
@onready var monster_deck_view_close: Button = $MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/CloseButton
@onready var monster_deck_view_stacked: CheckButton = $MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/StackedToggle

# Stored monster deck view data for stacked toggle
var _monster_deck_view_cards: Array[Dictionary] = []

# Zone stack view UI references
@onready var zone_stack_view_overlay: Control = $ZoneStackViewOverlay
@onready var zone_stack_view_title: Label = $ZoneStackViewOverlay/ZoneStackViewPanel/VBox/TitleLabel
@onready var zone_stack_view_grid: GridContainer = $ZoneStackViewOverlay/ZoneStackViewPanel/VBox/ScrollContainer/CardGrid
@onready var zone_stack_view_close: Button = $ZoneStackViewOverlay/ZoneStackViewPanel/VBox/CloseButton

# Card zoom overlay
@onready var card_zoom_overlay: Control = $CardZoomOverlay
@onready var card_zoom_container: CenterContainer = $CardZoomOverlay/CardContainer

# Card hover preview
var _preview_container: Control
var _preview_bg: Panel
var _preview_card: Control

# Stored zone stack view data
var _zone_stack_view_cards: Array[Dictionary] = []

# State tracking
var pending_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var waiting_for_card_select: bool = false
var waiting_for_zone_select: bool = false
var selected_card_id: String = ""
var _selected_card_data: Dictionary = {} # Card data dict for the selected card

# Hand discard selection state
var _discard_selecting: bool = false
var _discard_player_id: int = -1
var _discard_count: int = 0
var _discard_selected_cards: Array[Control] = []

# Hand card selection state (single-select for effects like ESD02-004)
var _hand_card_selecting: bool = false
var _hand_card_player_id: int = -1
var _hand_card_allow_skip: bool = false

# Action blocking — prevents input while an action is being processed
var _action_pending: bool = false

# Zone target selection state (for effects that let the player pick a zone)
var _zone_target_selecting: bool = false
var _zone_target_player_id: int = -1 # Who is choosing
var _zone_target_board_pid: int = -1 # Whose board the zones are on
var _zone_target_valid_zones: Array[int] = []
var _zone_target_allow_skip: bool = false

# Standby choice selection state (for choosing ability resolution order)
var _choice_selecting: bool = false
var _choice_player_id: int = -1
var _choice_buttons: Array[Button] = []
var _choice_container: VBoxContainer = null

# Drag-to-zone state
var _drag_card: Control = null
var _drag_valid_zones: Array[int] = []
var _zone_select_valid: Array[int] = []
var _drag_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var _drag_can_rage: bool = false
var _drag_can_invade: bool = false
var _snap_preview_slot = null # Slot or Control currently being snap-previewed


func _ready() -> void:
	is_multiplayer_game = NetworkManager.is_multiplayer()
	local_player_id = NetworkManager.get_local_player_id() if is_multiplayer_game else 0

	# Wire hand CardManagers to PlayerBoards
	player1_board.hand_manager = player1_hand
	player2_board.hand_manager = player2_hand

	# Rearrange layout for client so local player sees their board at bottom
	_arrange_for_local_player()

	if not is_multiplayer_game or NetworkManager.is_host():
		# Host / solo: create and run TurnManager
		turn_manager = TurnManager.new()
		turn_manager.setup(CardData)

		# Connect turn manager signals
		turn_manager.phase_started.connect(_on_phase_started)
		turn_manager.phase_ended.connect(_on_phase_ended)
		turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		turn_manager.turn_started.connect(_on_turn_started)
		turn_manager.game_ended.connect(_on_game_ended)
		turn_manager.log_message.connect(_on_log_message)

		# Connect action handler signals for visual feedback
		turn_manager.action_handler.battle_card_played.connect(_on_battle_card_played)
		turn_manager.action_handler.monster_advanced.connect(_on_monster_advanced)
		turn_manager.action_handler.battle_card_crushed.connect(_on_battle_card_crushed)
		turn_manager.action_handler.counter_succeeded.connect(_on_counter_succeeded)
		turn_manager.action_handler.counter_failed.connect(_on_counter_failed)
		turn_manager.action_handler.monster_countered.connect(_on_monster_countered)

		# Connect effect handler signals for player choice UIs
		turn_manager.action_handler.effect_handler.deck_search_requested.connect(_on_deck_search_requested)
		turn_manager.action_handler.effect_handler.hand_discard_requested.connect(_on_hand_discard_requested)
		turn_manager.action_handler.effect_handler.hand_card_selection_requested.connect(_on_hand_card_selection_requested)
		turn_manager.action_handler.effect_handler.zone_target_requested.connect(_on_zone_target_requested)
		turn_manager.action_handler.effect_handler.effect_zone_highlighted.connect(_on_effect_zone_highlighted)
		turn_manager.action_handler.effect_handler.effect_zone_unhighlighted.connect(_on_effect_zone_unhighlighted)
		turn_manager.action_handler.effect_handler.effect_card_highlighted.connect(_on_effect_card_highlighted)
		turn_manager.action_handler.effect_handler.effect_card_unhighlighted.connect(_on_effect_card_unhighlighted)
		turn_manager.action_handler.effect_handler.choice_requested.connect(_on_choice_requested)

		# Connect player state signals so mid-effect changes (e.g. search_deck adding
		# a card to hand) trigger visual updates immediately
		for player in turn_manager.game_state.players:
			player.hand_changed.connect(_on_state_changed)
			player.zones_changed.connect(_on_state_changed)
	else:
		# Client: initialize empty client state, wait for host RPCs
		_client_players = [PlayerState.new(0), PlayerState.new(1)]

	# Connect buttons
	btn_play_battle.pressed.connect(_on_play_battle_pressed)
	btn_play_strategy.pressed.connect(_on_play_strategy_pressed)
	btn_gain_rage.pressed.connect(_on_gain_rage_pressed)
	btn_play_monster.pressed.connect(_on_play_monster_pressed)
	btn_invade.pressed.connect(_on_invade_pressed)
	btn_pass.pressed.connect(_on_pass_pressed)

	# Connect hand drag signals for drag-to-zone
	player1_hand.hand_card_drag_started.connect(_on_hand_drag_started)
	player1_hand.hand_card_drag_ended.connect(_on_hand_drag_ended)
	player2_hand.hand_card_drag_started.connect(_on_hand_drag_started)
	player2_hand.hand_card_drag_ended.connect(_on_hand_drag_ended)

	# Connect hand right-click for card zoom (bind player_id to filter opponent's hand)
	player1_hand.hand_card_right_clicked.connect(_on_hand_card_right_clicked.bind(0))
	player2_hand.hand_card_right_clicked.connect(_on_hand_card_right_clicked.bind(1))

	# Listen for disconnects in multiplayer
	if is_multiplayer_game:
		NetworkManager.player_disconnected.connect(_on_opponent_disconnected)

	# Connect deck search buttons
	deck_search_skip.pressed.connect(_on_deck_search_skip)
	deck_search_show_all.toggled.connect(_on_deck_search_toggled)
	deck_search_stacked.toggled.connect(_on_deck_search_toggled)
	deck_search_view_board.pressed.connect(_on_deck_search_view_board)
	show_cards_button.pressed.connect(_on_show_cards_pressed)

	# Connect discard view
	player1_board.discard_clicked.connect(_on_discard_clicked)
	player2_board.discard_clicked.connect(_on_discard_clicked)
	discard_view_close.pressed.connect(_hide_discard_view)
	discard_view_overlay.gui_input.connect(_on_overlay_background_clicked.bind(_hide_discard_view))
	discard_view_stacked.toggled.connect(_on_discard_view_stacked_toggled)

	# Connect monster deck view
	player1_board.monster_deck_clicked.connect(_on_monster_deck_clicked)
	player2_board.monster_deck_clicked.connect(_on_monster_deck_clicked)
	monster_deck_view_close.pressed.connect(_hide_monster_deck_view)
	monster_deck_view_overlay.gui_input.connect(_on_overlay_background_clicked.bind(_hide_monster_deck_view))
	monster_deck_view_stacked.toggled.connect(_on_monster_deck_view_stacked_toggled)

	# Connect zone stack view
	player1_board.zone_slot_clicked.connect(_on_zone_slot_clicked)
	player2_board.zone_slot_clicked.connect(_on_zone_slot_clicked)
	zone_stack_view_close.pressed.connect(_hide_zone_stack_view)
	zone_stack_view_overlay.gui_input.connect(_on_overlay_background_clicked.bind(_hide_zone_stack_view))

	# Connect card zoom (right-click)
	player1_board.zone_slot_right_clicked.connect(_on_zone_slot_right_clicked)
	player2_board.zone_slot_right_clicked.connect(_on_zone_slot_right_clicked)
	player1_board.strategy_slot_right_clicked.connect(_on_strategy_slot_right_clicked)
	player2_board.strategy_slot_right_clicked.connect(_on_strategy_slot_right_clicked)
	card_zoom_overlay.gui_input.connect(_on_card_zoom_overlay_input)

	# Enable BBCode on log for hoverable card links (no underline)
	log_output.bbcode_enabled = true
	log_output.meta_underlined = false
	log_output.meta_hover_started.connect(_on_log_meta_hover_started)
	log_output.meta_hover_ended.connect(_on_log_meta_hover_ended)

	# Hide overlays and prompts
	end_game_panel.visible = false
	card_select_prompt.visible = false
	deck_search_overlay.visible = false
	show_cards_button.visible = false
	discard_view_overlay.visible = false
	monster_deck_view_overlay.visible = false
	zone_stack_view_overlay.visible = false
	card_zoom_overlay.visible = false

	# Card hover preview panel (right side of screen)
	_preview_container = Control.new()
	_preview_container.anchor_left = 0.75
	_preview_container.anchor_right = 0.995
	_preview_container.anchor_top = 0.05
	_preview_container.anchor_bottom = 0.75
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	# Initial board sync and start (host/solo only)
	if turn_manager:
		_sync_boards()
		call_deferred("_start_game")
	else:
		_disable_all_buttons()


func _start_game() -> void:
	turn_manager.start_game()


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

	# Local player hand: visible, centered in hand space
	if local_space and local_hand:
		var rect := local_space.get_global_rect()
		local_hand.global_position = Vector2(rect.position.x + rect.size.x * 0.35, rect.position.y + rect.size.y / 2.0)
		local_hand.max_width = rect.size.x * 0.95
		local_hand.arrange_cards(false)

	# Opponent hand: mostly off-screen at top edge
	if opponent_space and opponent_hand:
		var rect := opponent_space.get_global_rect()
		opponent_hand.global_position = Vector2(rect.position.x + rect.size.x * 0.35, rect.position.y - 195.0)
		opponent_hand.max_width = rect.size.x * 0.95
		opponent_hand.arrange_cards(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_position_hands")


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
	_disable_all_buttons()
	if not is_multiplayer_game or NetworkManager.is_host():
		turn_manager.submit_action(action, params)
	else:
		var params_json := JSON.stringify(params) if not params.is_empty() else ""
		_rpc_submit_action.rpc_id(1, int(action), params_json)


# --- Signal handlers from TurnManager (host/solo only) ---

func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	phase_label.text = CardEnums.phase_to_string(phase)
	_sync_boards()
	_broadcast_state()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()
	_broadcast_state()


func _on_turn_started(player_id: int) -> void:
	turn_label.text = "Turn %d - Player %d" % [turn_manager.game_state.turn_number, player_id + 1]
	_sync_boards()
	_update_hand_visibility(player_id)
	_broadcast_state()


func _on_awaiting_action(valid_actions: Array) -> void:
	_action_pending = false
	_sync_boards()

	if is_multiplayer_game:
		_broadcast_state()
		var active_id := turn_manager.game_state.current_player_id

		# Compute playable indices for the active player
		var playable := _compute_playable_data()
		var actions_json := JSON.stringify(valid_actions)
		var playable_json := JSON.stringify(playable)

		if active_id == local_player_id:
			# Host's turn
			_client_playable = playable
			_update_action_buttons(valid_actions)
		else:
			# Client's turn — send context, disable host buttons
			_disable_all_buttons()
			for peer_id in NetworkManager.peer_player_map:
				if NetworkManager.peer_player_map[peer_id] == active_id:
					_rpc_receive_action_context.rpc_id(peer_id, actions_json, playable_json)
	else:
		_update_action_buttons(valid_actions)


func _on_game_ended(winner_id: int, reason: String) -> void:
	_action_pending = false
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Player %d Wins!\n%s" % [winner_id + 1, reason]
	_disable_all_buttons()
	if is_multiplayer_game and NetworkManager.is_host():
		_rpc_receive_game_ended.rpc(winner_id, reason)


func _on_state_changed() -> void:
	_sync_boards()
	if not _discard_selecting:
		_update_hand_visibility(_get_current_pid())
	_broadcast_state()


func _on_log_message(text: String) -> void:
	if log_output:
		log_output.append_text(text + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)
	if is_multiplayer_game and NetworkManager.is_host():
		_rpc_receive_log.rpc(text)


# --- Action handler visual feedback ---

func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	_sync_boards()
	_broadcast_state()


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	_sync_boards()
	_broadcast_state()


func _on_battle_card_crushed(player_id: int, zone_index: int, card: Dictionary) -> void:
	_on_log_message("Battle card '%s' crushed in P%d Zone %d!" % [card.get("name", "?"), player_id + 1, zone_index + 1])
	_sync_boards()
	_broadcast_state()


func _on_counter_succeeded(player_id: int, total_cp: int, threat: int) -> void:
	_on_log_message("Counter SUCCESS! P%d CP %d >= Threat %d" % [player_id + 1, total_cp, threat])
	_sync_boards()
	_broadcast_state()


func _on_counter_failed(player_id: int, total_cp: int, threat: int) -> void:
	_on_log_message("Counter failed. P%d CP %d < Threat %d" % [player_id + 1, total_cp, threat])


func _on_monster_countered(_player_id: int, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	_sync_boards()
	_broadcast_state()


# --- Button handlers ---

func _on_play_battle_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		var state := turn_manager.game_state
		playable = turn_manager.rules_engine.get_playable_battle_cards(state.get_current_player(), state.get_opponent_of_current())
	else:
		playable.assign(_client_playable.get("battle_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_BATTLE
	_enter_card_selection("Select a BATTLE card to play:", playable)


func _on_play_strategy_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_playable_strategy_cards(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("strategy_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_STRATEGY
	_enter_card_selection("Select a STRATEGY card to activate:", playable)


func _on_gain_rage_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_monster_cards_for_rage(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("rage_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.GAIN_RAGE
	_enter_card_selection("Select a MONSTER card to discard for Rage:", playable)


func _on_play_monster_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_playable_monsters(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("monster_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_MONSTER
	_enter_card_selection("Select a MONSTER card to play:", playable)


func _on_invade_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_discardable_cards_for_invade(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("invade_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.INVADE
	_enter_card_selection("Select a card to discard for Invasion:", playable)


func _on_pass_pressed() -> void:
	if _hand_card_selecting and _hand_card_allow_skip:
		_skip_hand_card_selection()
		return
	if _zone_target_selecting and _zone_target_allow_skip:
		_skip_zone_target()
		return
	if _discard_selecting and _discard_selected_cards.size() == _discard_count:
		_confirm_hand_discard()
		return
	if waiting_for_card_select or waiting_for_zone_select:
		_cancel_selection()
		if turn_manager:
			_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
		else:
			_update_action_buttons(_client_playable.get("valid_actions", []))
		return
	_cancel_selection()
	_submit_action(CardEnums.ActionType.PASS)


# --- Card selection flow ---

func _enter_card_selection(prompt_text: String, valid_indices: Array[int]) -> void:
	waiting_for_card_select = true
	card_select_prompt.text = prompt_text
	card_select_prompt.visible = true
	_disable_all_buttons()
	btn_pass.disabled = false
	btn_pass.text = "Cancel"

	var board := _get_active_player_board()
	if board and board.hand_manager:
		var visual_indices := _hand_indices_to_visual(valid_indices, board)
		board.hand_manager.enter_selection_mode(visual_indices)
		if not board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
			board.hand_manager.card_selected.connect(_on_hand_card_selected)


func _on_hand_card_selected(card: Control, _visual_index: int) -> void:
	if not waiting_for_card_select:
		return

	_selected_card_data = card.card_data if "card_data" in card else {}
	selected_card_id = _selected_card_data.get("id", "")
	if selected_card_id.is_empty():
		return

	match pending_action:
		CardEnums.ActionType.PLAY_BATTLE:
			_enter_zone_selection()
		CardEnums.ActionType.PLAY_STRATEGY:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": idx})
		CardEnums.ActionType.GAIN_RAGE:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": idx})
		CardEnums.ActionType.PLAY_MONSTER:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": idx})
		CardEnums.ActionType.INVADE:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.INVADE, {"hand_index": idx})


func _enter_zone_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = true
	card_select_prompt.text = "Select a ZONE to place the battle card:"

	var valid_zones: Array[int] = []
	if turn_manager:
		var state := turn_manager.game_state
		var player := state.get_current_player()
		var opponent := state.get_opponent_of_current()
		if not _selected_card_data.is_empty():
			valid_zones = turn_manager.rules_engine.get_valid_zones_for_card(_selected_card_data, player, opponent)
		else:
			valid_zones = turn_manager.rules_engine.get_valid_zones_for_battle_card(player, opponent)
	else:
		var card_id: String = _selected_card_data.get("id", "")
		var zones_data = _client_playable.get("battle_zones", {})
		if zones_data is Dictionary:
			valid_zones.assign(zones_data.get(card_id, []))
		else:
			valid_zones.assign(zones_data)

	_zone_select_valid = valid_zones

	var board := _get_active_player_board()
	if board:
		board.hand_manager.exit_selection_mode()
		board.highlight_valid_zones(valid_zones)
		for i in range(board.zone_slots.size()):
			var slot: Slot = board.zone_slots[i]
			if i in valid_zones:
				slot.in_selection_mode = true
				slot.accept_cards = true
				if not slot.card_placed.is_connected(_on_zone_slot_clicked):
					slot.card_placed.connect(_on_zone_slot_clicked.bind(i))
				if not slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.connect(_on_zone_hover_clicked.bind(i))


func _on_zone_hover_clicked(_zone_index: int) -> void:
	if not waiting_for_zone_select:
		return
	pass


func _process(_delta: float) -> void:
	if not _drag_card or not _drag_card.is_dragging:
		if _snap_preview_slot:
			_end_snap_preview()
		return
	_update_snap_preview()


func _update_snap_preview() -> void:
	var board := _get_active_player_board()
	if not board:
		return

	var mouse_pos := get_global_mouse_position()
	var hovered_slot = null # Slot or Control

	# Check zone slots
	for i in _drag_valid_zones:
		if i < 0 or i >= board.zone_slots.size():
			continue
		var slot: Slot = board.zone_slots[i]
		if slot and Rect2(slot.global_position, slot.size).has_point(mouse_pos):
			hovered_slot = slot
			break

	# Check strategy slots
	if not hovered_slot and _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
		for slot in board.strategy_slots:
			if slot and not slot.has_card() and Rect2(slot.global_position, slot.size).has_point(mouse_pos):
				hovered_slot = slot
				break

	# Check rage zone
	if not hovered_slot and _drag_can_rage and board.rage_display:
		if Rect2(board.rage_display.global_position, board.rage_display.size).has_point(mouse_pos):
			hovered_slot = board.rage_display

	# Check discard zone
	if not hovered_slot and _drag_can_invade and board.discard_display:
		if Rect2(board.discard_display.global_position, board.discard_display.size).has_point(mouse_pos):
			hovered_slot = board.discard_display

	if hovered_slot == _snap_preview_slot:
		return # No change

	if _snap_preview_slot and hovered_slot != _snap_preview_slot:
		_end_snap_preview()

	if hovered_slot:
		_start_snap_preview(hovered_slot)


func _start_snap_preview(target) -> void:
	_snap_preview_slot = target

	# Compute snap position and scale based on target type
	var target_rect: Rect2
	if target is Slot:
		# Use the slot's content rect (card aspect ratio area) for precise positioning
		var content_rect: Rect2 = target._content_rect
		target_rect = Rect2(target.global_position + content_rect.position, content_rect.size)
	else:
		# For non-slot targets (rage/discard display), use the full control rect
		target_rect = Rect2(target.global_position, target.size)

	# Calculate scale to fit card in the target area (maintain aspect ratio)
	var card_size: Vector2 = _drag_card.size # Base card size (150x210)
	var scale_x := target_rect.size.x / card_size.x
	var scale_y := target_rect.size.y / card_size.y
	var fit_scale := minf(scale_x, scale_y)
	var target_scale := Vector2(fit_scale, fit_scale)

	# Position: center the scaled card within the target rect
	var scaled_size := card_size * fit_scale
	var target_pos := target_rect.position + (target_rect.size - scaled_size) / 2.0

	_drag_card.start_snap_preview(target_pos, target_scale)


func _end_snap_preview() -> void:
	_snap_preview_slot = null
	if _drag_card and _drag_card.is_snap_previewing:
		_drag_card.end_snap_preview()


func _input(event: InputEvent) -> void:
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


func _cancel_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_card_id = ""
	_selected_card_data = {}
	_zone_select_valid = []
	card_select_prompt.visible = false
	btn_pass.text = "Pass"

	for board in [player1_board, player2_board]:
		if board and board.hand_manager:
			board.hand_manager.exit_selection_mode()
			if board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
				board.hand_manager.card_selected.disconnect(_on_hand_card_selected)
		if board:
			board.clear_highlights()
			for slot in board.zone_slots:
				slot.in_selection_mode = false
				if slot.card_placed.is_connected(_on_zone_slot_clicked):
					slot.card_placed.disconnect(_on_zone_slot_clicked)
				if slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.disconnect(_on_zone_hover_clicked)


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
		var cp_mod_0: int = 0
		var cp_mod_1: int = 0
		for v in zone_cp_0: cp_mod_0 += v
		for v in zone_cp_1: cp_mod_1 += v
		var threat_mod_0: int = eh.get_threat_level_modifier(0) if eh else 0
		var threat_mod_1: int = eh.get_threat_level_modifier(1) if eh else 0
		if player1_board and not skip_p1:
			player1_board.sync_to_state(state.players[0], cp_mod_0, threat_mod_0, zone_cp_0)
		if player2_board and not skip_p2:
			player2_board.sync_to_state(state.players[1], cp_mod_1, threat_mod_1, zone_cp_1)
	elif not _client_players.is_empty():
		if player1_board and not skip_p1:
			player1_board.sync_to_state(_client_players[0], _client_cp_modifiers[0], _client_threat_modifiers[0], _client_zone_cp_mods[0])
		if player2_board and not skip_p2:
			player2_board.sync_to_state(_client_players[1], _client_cp_modifiers[1], _client_threat_modifiers[1], _client_zone_cp_mods[1])
	call_deferred("_position_hands")


func _update_hand_visibility(active_player_id: int) -> void:
	if is_multiplayer_game:
		# Multiplayer: local player always face-up, opponent always face-down
		if player1_board:
			player1_board.set_hand_face_down(local_player_id != 0)
		if player2_board:
			player2_board.set_hand_face_down(local_player_id != 1)
	else:
		# Solo: active player face-up, opponent face-down
		if player1_board:
			player1_board.set_hand_face_down(active_player_id != 0)
		if player2_board:
			player2_board.set_hand_face_down(active_player_id != 1)


func _update_action_buttons(valid_actions: Array) -> void:
	btn_play_battle.disabled = CardEnums.ActionType.PLAY_BATTLE not in valid_actions
	btn_play_strategy.disabled = CardEnums.ActionType.PLAY_STRATEGY not in valid_actions
	btn_gain_rage.disabled = CardEnums.ActionType.GAIN_RAGE not in valid_actions
	btn_play_monster.disabled = CardEnums.ActionType.PLAY_MONSTER not in valid_actions
	btn_invade.disabled = CardEnums.ActionType.INVADE not in valid_actions
	btn_pass.disabled = false
	btn_pass.visible = true
	btn_pass.text = "Pass"
	card_select_prompt.visible = false


func _disable_all_buttons() -> void:
	btn_play_battle.disabled = true
	btn_play_strategy.disabled = true
	btn_gain_rage.disabled = true
	btn_play_monster.disabled = true
	btn_invade.disabled = true
	btn_pass.disabled = true


func _get_active_player_board() -> Control:
	var active_id: int = _get_current_pid()
	if active_id == 0:
		return player1_board
	else:
		return player2_board


## Translate player.hand indices to managed_cards indices by matching card IDs
func _hand_indices_to_visual(hand_indices: Array[int], board: Control) -> Array[int]:
	var player := _get_current_player()
	var visual: Array[int] = []
	var cards: Array[Control] = board.hand_manager.get_cards()
	for hand_idx in hand_indices:
		if hand_idx >= player.hand.size():
			continue
		var card_id: String = player.hand[hand_idx].get("id", "")
		for j in range(cards.size()):
			if "card_data" in cards[j] and cards[j].card_data.get("id") == card_id:
				visual.append(j)
				break
	return visual


## Find a card's index in player.hand by its unique ID
func _find_hand_index_by_id(card_id: String) -> int:
	var player := _get_current_player()
	for i in range(player.hand.size()):
		if player.hand[i].get("id") == card_id:
			return i
	return -1


# --- Drag-to-zone ---

func _on_hand_drag_started(card: Control) -> void:
	if _action_pending:
		return
	if waiting_for_card_select or waiting_for_zone_select:
		return
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty():
		return

	var player := _get_current_player()
	var board := _get_active_player_board()
	if not board:
		return

	if board.hand_manager != card.get_parent():
		return

	var card_type = card_data.get("card_type", -1)
	_drag_card = card
	_drag_valid_zones = []
	_drag_action = CardEnums.ActionType.PASS
	_drag_can_rage = false
	_drag_can_invade = false
	_snap_preview_slot = null

	if card_type == CardEnums.CardType.BATTLE:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var playable_battle: Array[int] = []
			var valid_zones: Array[int] = []
			if turn_manager:
				var opponent := turn_manager.game_state.get_opponent_of_current()
				playable_battle = turn_manager.rules_engine.get_playable_battle_cards(player, opponent)
				valid_zones = turn_manager.rules_engine.get_valid_zones_for_card(card_data, player, opponent)
			else:
				playable_battle.assign(_client_playable.get("battle_cards", []))
				var zones_data = _client_playable.get("battle_zones", {})
				if zones_data is Dictionary:
					valid_zones.assign(zones_data.get(card_id, []))
				else:
					valid_zones.assign(zones_data)
			if hand_idx in playable_battle:
				_drag_valid_zones = valid_zones
				_drag_action = CardEnums.ActionType.PLAY_BATTLE

	elif card_type == CardEnums.CardType.MONSTER:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			# Check if this monster can be played onto the current monster
			var playable_monsters: Array[int] = []
			if turn_manager:
				playable_monsters = turn_manager.rules_engine.get_playable_monsters(player)
			else:
				playable_monsters.assign(_client_playable.get("monster_cards", []))
			if hand_idx in playable_monsters:
				var monster_zone_idx: int = player.monster_zone - 1
				if monster_zone_idx >= 0 and monster_zone_idx < 8:
					_drag_valid_zones = [monster_zone_idx]
					_drag_action = CardEnums.ActionType.PLAY_MONSTER
			# Any monster card can also be discarded for rage
			var rage_cards: Array[int] = []
			if turn_manager:
				rage_cards = turn_manager.rules_engine.get_monster_cards_for_rage(player)
			else:
				rage_cards.assign(_client_playable.get("rage_cards", []))
			if hand_idx in rage_cards:
				_drag_can_rage = true

	elif card_type == CardEnums.CardType.STRATEGY:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var playable_strategy: Array[int] = []
			if turn_manager:
				playable_strategy = turn_manager.rules_engine.get_playable_strategy_cards(player)
			else:
				playable_strategy.assign(_client_playable.get("strategy_cards", []))
			if hand_idx in playable_strategy:
				_drag_action = CardEnums.ActionType.PLAY_STRATEGY

	# Any card with invasion_icon > 0 can be discarded for invasion
	if card_data.get("invasion_icon", 0) > 0:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var invade_cards: Array[int] = []
			if turn_manager:
				invade_cards = turn_manager.rules_engine.get_discardable_cards_for_invade(player)
			else:
				invade_cards.assign(_client_playable.get("invade_cards", []))
			if hand_idx in invade_cards:
				_drag_can_invade = true

	if not _drag_valid_zones.is_empty():
		board.highlight_valid_zones(_drag_valid_zones)
	if _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
		board.highlight_strategy_zones()
	if _drag_can_rage:
		board.highlight_rage_zone(true)
	if _drag_can_invade:
		board.highlight_discard_zone(true)


func _on_hand_drag_ended(card: Control) -> void:
	_end_snap_preview()

	var board := _get_active_player_board()

	if board:
		board.clear_highlights()

	var has_drag_target := not _drag_valid_zones.is_empty() or _drag_action == CardEnums.ActionType.PLAY_STRATEGY or _drag_can_rage or _drag_can_invade
	if _drag_card != card or not has_drag_target:
		_drag_card = null
		_drag_valid_zones = []
		_drag_can_rage = false
		_drag_can_invade = false
		return

	var mouse_pos := get_global_mouse_position()
	if board:
		# Check rage zone drop (monster cards discarded for rage)
		if _drag_can_rage and board.rage_display:
			var rage_rect := Rect2(board.rage_display.global_position, board.rage_display.size)
			if rage_rect.has_point(mouse_pos):
				var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
				var hand_idx := _find_hand_index_by_id(card_id)
				if hand_idx >= 0:
					board.hand_manager.drop_handled = true
					_drag_card = null
					_drag_valid_zones = []
					_drag_can_rage = false
					_drag_can_invade = false
					_submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": hand_idx})
					return

		# Check discard zone drop (cards with invasion_icon discarded for invasion)
		if _drag_can_invade and board.discard_display:
			var discard_rect := Rect2(board.discard_display.global_position, board.discard_display.size)
			if discard_rect.has_point(mouse_pos):
				var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
				var hand_idx := _find_hand_index_by_id(card_id)
				if hand_idx >= 0:
					board.hand_manager.drop_handled = true
					_drag_card = null
					_drag_valid_zones = []
					_drag_can_rage = false
					_drag_can_invade = false
					_submit_action(CardEnums.ActionType.INVADE, {"hand_index": hand_idx})
					return

		# Strategy cards target strategy slots (auto-placed, no zone_index needed)
		if _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
			for slot in board.strategy_slots:
				if slot and not slot.has_card():
					var rect := Rect2(slot.global_position, slot.size)
					if rect.has_point(mouse_pos):
						var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
						var hand_idx := _find_hand_index_by_id(card_id)
						if hand_idx >= 0:
							board.hand_manager.drop_handled = true
							_drag_card = null
							_drag_valid_zones = []
							_submit_action(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": hand_idx})
							return
		else:
			for i in _drag_valid_zones:
				var slot: Slot = board.zone_slots[i]
				var rect := Rect2(slot.global_position, slot.size)
				var is_valid_target: bool = false
				is_valid_target = rect.has_point(mouse_pos)
				if is_valid_target:
					var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
					var hand_idx := _find_hand_index_by_id(card_id)
					if hand_idx >= 0:
						board.hand_manager.drop_handled = true
						_drag_card = null
						_drag_valid_zones = []
						var params := {"hand_index": hand_idx}
						if _drag_action != CardEnums.ActionType.PLAY_MONSTER:
							params["zone_index"] = i
						_submit_action(_drag_action, params)
						return

	_drag_card = null
	_drag_valid_zones = []
	_drag_can_rage = false
	_drag_can_invade = false


# --- Deck search UI ---

func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String) -> void:
	if is_multiplayer_game and player_id != local_player_id:
		# Forward to the remote client who needs to make the choice
		var matching_json := JSON.stringify(matching_cards)
		var all_json := JSON.stringify(all_cards)
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				_rpc_deck_search_requested.rpc_id(peer_id, matching_json, all_json, prompt)
		return
	_show_deck_search(matching_cards, all_cards, prompt)


func _show_deck_search(matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String) -> void:
	# Store data for toggling
	_deck_search_matching = matching
	_deck_search_all = all_cards
	_deck_search_matching_ids.clear()
	for card_data in matching:
		_deck_search_matching_ids[card_data.get("id", "")] = true

	deck_search_prompt.text = prompt
	deck_search_show_all.set_pressed_no_signal(false)
	deck_search_stacked.set_pressed_no_signal(false)
	deck_search_overlay.visible = true

	_refresh_deck_search_grid()


func _refresh_deck_search_grid() -> void:
	var show_all := deck_search_show_all.button_pressed
	var stacked := deck_search_stacked.button_pressed
	var cards: Array[Dictionary] = _deck_search_all if show_all else _deck_search_matching
	var all_selectable: bool = not show_all

	# Clear previous cards
	_clear_grid(deck_search_grid, _on_deck_search_card_clicked)

	if stacked:
		var groups := _group_cards(cards)
		for group in groups:
			var card_data: Dictionary = group["card_data"]
			var count: int = group["count"]
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.drag_enabled = false
			_set_gallery_hover(card)
			var is_match: bool = all_selectable or group["has_match"]
			card.is_selectable = is_match
			if is_match:
				card.card_clicked.connect(_on_deck_search_card_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			deck_search_grid.add_child(card)
			_add_count_badge(card, count)
	else:
		for card_data in cards:
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.drag_enabled = false
			_set_gallery_hover(card)
			var is_match: bool = all_selectable or _deck_search_matching_ids.has(card_data.get("id", ""))
			card.is_selectable = is_match
			if is_match:
				card.card_clicked.connect(_on_deck_search_card_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			deck_search_grid.add_child(card)


func _on_deck_search_toggled(_value: bool) -> void:
	_refresh_deck_search_grid()


func _on_deck_search_view_board() -> void:
	deck_search_overlay.visible = false
	show_cards_button.visible = true


func _on_show_cards_pressed() -> void:
	show_cards_button.visible = false
	deck_search_overlay.visible = true


func _on_deck_search_card_clicked(card: Control) -> void:
	var selected: Dictionary = card.card_data if "card_data" in card else {}
	_hide_deck_search()
	_resolve_deck_search_local(selected)


func _on_deck_search_skip() -> void:
	_hide_deck_search()
	_resolve_deck_search_local({})


func _hide_deck_search() -> void:
	deck_search_overlay.visible = false
	show_cards_button.visible = false
	_clear_grid(deck_search_grid, _on_deck_search_card_clicked)
	_deck_search_matching.clear()
	_deck_search_all.clear()
	_deck_search_matching_ids.clear()


# --- Hand discard selection UI ---

func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if is_multiplayer_game and player_id != local_player_id:
		# Forward to the remote client who needs to make the choice
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				_rpc_hand_discard_requested.rpc_id(peer_id, discard_count)
		return
	_show_hand_discard_selection(player_id, discard_count)


func _show_hand_discard_selection(player_id: int, discard_count: int) -> void:
	_discard_selecting = true
	_discard_player_id = player_id
	_discard_count = discard_count
	_discard_selected_cards.clear()

	# Flip target player's hand face-up so they can see their cards
	var board: Control = player1_board if player_id == 0 else player2_board
	board.set_hand_face_down(false)

	var hand_mgr: CardManager = player1_hand if player_id == 0 else player2_hand
	# Make all cards selectable
	var all_indices: Array[int] = []
	for i in range(hand_mgr.managed_cards.size()):
		all_indices.append(i)
	hand_mgr.enter_selection_mode(all_indices)
	if not hand_mgr.card_selected.is_connected(_on_discard_card_selected):
		hand_mgr.card_selected.connect(_on_discard_card_selected)

	_disable_all_buttons()
	card_select_prompt.text = "Select %d card%s to discard:" % [discard_count, "" if discard_count == 1 else "s"]
	card_select_prompt.visible = true
	btn_pass.visible = false


func _on_discard_card_selected(card: Control, _index: int) -> void:
	if not _discard_selecting:
		return

	# Toggle selection: if already selected, deselect; otherwise select
	if card in _discard_selected_cards:
		_discard_selected_cards.erase(card)
		card.modulate = Color.WHITE
	else:
		if _discard_selected_cards.size() < _discard_count:
			_discard_selected_cards.append(card)
			card.modulate = Color(1.0, 0.5, 0.5, 1.0)

	# Update prompt and confirm button
	var remaining: int = _discard_count - _discard_selected_cards.size()
	if remaining > 0:
		card_select_prompt.text = "Select %d more card%s to discard:" % [remaining, "" if remaining == 1 else "s"]
		btn_pass.visible = false
	else:
		card_select_prompt.text = "Press Confirm to discard selected cards"
		btn_pass.text = "Confirm"
		btn_pass.visible = true
		btn_pass.disabled = false


func _confirm_hand_discard() -> void:
	var hand_mgr: CardManager = player1_hand if _discard_player_id == 0 else player2_hand

	# Build hand indices from selected cards
	var hand_indices: Array[int] = []
	var player := _get_player_state(_discard_player_id)
	for card in _discard_selected_cards:
		if "card_data" in card:
			var card_id: String = card.card_data.get("id", "")
			for i in range(player.hand.size()):
				if player.hand[i].get("id", "") == card_id and i not in hand_indices:
					hand_indices.append(i)
					break

	# Reset visual state
	for card in _discard_selected_cards:
		card.modulate = Color.WHITE
	_discard_selected_cards.clear()
	_discard_selecting = false

	hand_mgr.exit_selection_mode()
	if hand_mgr.card_selected.is_connected(_on_discard_card_selected):
		hand_mgr.card_selected.disconnect(_on_discard_card_selected)
	card_select_prompt.visible = false
	btn_pass.text = "Pass"
	btn_pass.visible = true

	# Restore hand visibility
	_update_hand_visibility(_get_current_pid())

	if is_multiplayer_game and _discard_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		# Client sends choice to host
		var indices_json := JSON.stringify(hand_indices)
		_rpc_hand_discard_resolved.rpc_id(1, indices_json)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_discard(_discard_player_id, hand_indices)


func _force_cleanup_discard_selection() -> void:
	## Emergency cleanup of discard selection state (e.g. when receiving new action context).
	for card in _discard_selected_cards:
		if is_instance_valid(card):
			card.modulate = Color.WHITE
	_discard_selected_cards.clear()
	_discard_selecting = false
	_discard_player_id = -1
	_discard_count = 0

	for hand_mgr in [player1_hand, player2_hand]:
		hand_mgr.exit_selection_mode()
		if hand_mgr.card_selected.is_connected(_on_discard_card_selected):
			hand_mgr.card_selected.disconnect(_on_discard_card_selected)

	card_select_prompt.visible = false
	btn_pass.text = "Pass"
	btn_pass.visible = true

	_update_hand_visibility(_get_current_pid())


# --- Hand card selection UI (single-select for effects) ---

func _on_hand_card_selection_requested(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> void:
	if is_multiplayer_game and player_id != local_player_id:
		# Forward to the remote client who needs to make the choice
		var indices_json := JSON.stringify(valid_indices)
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				_rpc_hand_card_selection_requested.rpc_id(peer_id, indices_json, prompt, allow_skip)
		return
	_show_hand_card_selection(player_id, valid_indices, prompt, allow_skip)


func _show_hand_card_selection(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> void:
	_hand_card_selecting = true
	_hand_card_player_id = player_id
	_hand_card_allow_skip = allow_skip

	# Flip target player's hand face-up so they can see their cards
	var board: Control = player1_board if player_id == 0 else player2_board
	board.set_hand_face_down(false)

	var hand_mgr: CardManager = player1_hand if player_id == 0 else player2_hand
	hand_mgr.enter_selection_mode(valid_indices)
	if not hand_mgr.card_selected.is_connected(_on_hand_card_clicked):
		hand_mgr.card_selected.connect(_on_hand_card_clicked)

	_disable_all_buttons()
	card_select_prompt.text = prompt
	card_select_prompt.visible = true

	if allow_skip:
		btn_pass.text = "Skip"
		btn_pass.visible = true
		btn_pass.disabled = false
	else:
		btn_pass.visible = false


func _on_hand_card_clicked(card: Control, _index: int) -> void:
	if not _hand_card_selecting:
		return

	# Single-select: find the hand index and resolve immediately
	var hand_mgr: CardManager = player1_hand if _hand_card_player_id == 0 else player2_hand
	var player := _get_player_state(_hand_card_player_id)
	var hand_index: int = -1
	if "card_data" in card:
		var card_id: String = card.card_data.get("id", "")
		for i in range(player.hand.size()):
			if player.hand[i].get("id", "") == card_id:
				hand_index = i
				break

	_cleanup_hand_card_selection(hand_mgr)

	if is_multiplayer_game and _hand_card_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		_rpc_hand_card_selection_resolved.rpc_id(1, hand_index)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_card_selection(hand_index)


func _skip_hand_card_selection() -> void:
	var hand_mgr: CardManager = player1_hand if _hand_card_player_id == 0 else player2_hand
	_cleanup_hand_card_selection(hand_mgr)

	if is_multiplayer_game and _hand_card_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		_rpc_hand_card_selection_resolved.rpc_id(1, -1)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_card_selection(-1)


func _cleanup_hand_card_selection(hand_mgr: CardManager) -> void:
	_hand_card_selecting = false
	hand_mgr.exit_selection_mode()
	if hand_mgr.card_selected.is_connected(_on_hand_card_clicked):
		hand_mgr.card_selected.disconnect(_on_hand_card_clicked)
	card_select_prompt.visible = false
	btn_pass.text = "Pass"
	btn_pass.visible = true
	_update_hand_visibility(_get_current_pid())


# --- Zone target selection UI ---

func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> void:
	if is_multiplayer_game and player_id != local_player_id:
		# Forward to the remote client who needs to make the choice
		var zones_json := JSON.stringify(valid_zones)
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				_rpc_zone_target_requested.rpc_id(peer_id, target_player_id, zones_json, prompt, allow_skip)
		return
	_show_zone_target_selection(player_id, target_player_id, valid_zones, prompt, allow_skip)


func _show_zone_target_selection(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool = false) -> void:
	_zone_target_selecting = true
	_zone_target_player_id = player_id
	_zone_target_board_pid = target_player_id
	_zone_target_valid_zones = valid_zones
	_zone_target_allow_skip = allow_skip

	_disable_all_buttons()
	card_select_prompt.text = prompt
	card_select_prompt.visible = true

	if allow_skip:
		btn_pass.text = "Skip"
		btn_pass.visible = true
		btn_pass.disabled = false
	else:
		btn_pass.visible = false

	# Highlight valid zones on the target player's board
	var board: Control = player1_board if target_player_id == 0 else player2_board
	board.highlight_valid_zones(valid_zones)
	for i in range(board.zone_slots.size()):
		var slot: Slot = board.zone_slots[i]
		if slot and i in valid_zones:
			slot.in_selection_mode = true
			if not slot.slot_clicked.is_connected(_on_zone_target_slot_clicked):
				slot.slot_clicked.connect(_on_zone_target_slot_clicked)


func _on_zone_target_slot_clicked(zone_num: int, _pid: int) -> void:
	if not _zone_target_selecting:
		return
	var zone_idx: int = zone_num - 1
	if zone_idx not in _zone_target_valid_zones:
		return
	_finish_zone_target(zone_idx)


func _skip_zone_target() -> void:
	_finish_zone_target(-1)


func _finish_zone_target(zone_idx: int) -> void:
	# Clean up UI
	var board: Control = player1_board if _zone_target_board_pid == 0 else player2_board
	board.clear_highlights()
	for i in range(board.zone_slots.size()):
		var slot: Slot = board.zone_slots[i]
		if slot:
			slot.in_selection_mode = false
			if slot.slot_clicked.is_connected(_on_zone_target_slot_clicked):
				slot.slot_clicked.disconnect(_on_zone_target_slot_clicked)

	_zone_target_selecting = false
	_zone_target_allow_skip = false
	card_select_prompt.visible = false
	btn_pass.text = "Pass"
	btn_pass.visible = true

	if is_multiplayer_game and not NetworkManager.is_host():
		_rpc_zone_target_resolved.rpc_id(1, zone_idx)
	else:
		turn_manager.action_handler.effect_handler.resolve_zone_target(zone_idx)


# --- Standby ability order choice UI ---

func _on_choice_requested(player_id: int, options: Array[String], prompt: String) -> void:
	if is_multiplayer_game and player_id != local_player_id:
		var options_json := JSON.stringify(options)
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				_rpc_choice_requested.rpc_id(peer_id, options_json, prompt)
		return
	_show_choice_selection(player_id, options, prompt)


func _show_choice_selection(player_id: int, options: Array[String], prompt: String) -> void:
	_choice_selecting = true
	_choice_player_id = player_id

	_disable_all_buttons()
	# Hide the normal action button rows so only choice buttons show
	action_panel.get_node("Row1").visible = false
	action_panel.get_node("Row2").visible = false
	card_select_prompt.text = prompt
	card_select_prompt.visible = true

	# Create a container for choice buttons inside the action panel
	_choice_container = VBoxContainer.new()
	_choice_container.name = "ChoiceContainer"
	action_panel.add_child(_choice_container)

	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.pressed.connect(_on_choice_button_pressed.bind(i))
		_choice_container.add_child(btn)
		_choice_buttons.append(btn)


func _on_choice_button_pressed(index: int) -> void:
	if not _choice_selecting:
		return
	_cleanup_choice_selection()

	if is_multiplayer_game and not NetworkManager.is_host():
		_rpc_choice_resolved.rpc_id(1, index)
	else:
		turn_manager.action_handler.effect_handler.resolve_choice(index)


func _cleanup_choice_selection() -> void:
	_choice_selecting = false
	_choice_buttons.clear()
	if _choice_container:
		_choice_container.queue_free()
		_choice_container = null
	card_select_prompt.visible = false
	# Restore normal action button rows
	action_panel.get_node("Row1").visible = true
	action_panel.get_node("Row2").visible = true
	btn_pass.text = "Pass"
	btn_pass.visible = true


func _on_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if is_multiplayer_game and pid != local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				_rpc_effect_zone_highlighted.rpc_id(peer_id, pid, zone_index)
		return
	_apply_zone_highlight(pid, zone_index, true)


func _on_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if is_multiplayer_game and pid != local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				_rpc_effect_zone_unhighlighted.rpc_id(peer_id, pid, zone_index)
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
			_rpc_effect_card_highlighted.rpc_id(peer_id, pid, card_id)
	_apply_card_highlight(pid, card_id, true)


func _on_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if is_multiplayer_game:
		for peer_id in NetworkManager.peer_player_map:
			_rpc_effect_card_unhighlighted.rpc_id(peer_id, pid, card_id)
	_apply_card_highlight(pid, card_id, false)


func _apply_card_highlight(pid: int, card_id: String, highlighted: bool) -> void:
	var board: Control = player1_board if pid == 0 else player2_board
	var color := Color(1.2, 1.2, 0.6, 1.0) if highlighted else Color.WHITE
	# Check zone slots (battle cards)
	for slot in board.zone_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == card_id:
			slot.held_card.modulate = color
			return
	# Check strategy slots
	for slot in board.strategy_slots:
		if slot and slot.held_card and slot.held_card.card_data.get("id", "") == card_id:
			slot.held_card.modulate = color
			return


# --- Discard view UI ---

func _on_discard_clicked(pid: int) -> void:
	var player := _get_player_state(pid)
	_discard_view_cards = player.discard_pile.duplicate(true)
	var title := "Player %d Discard Pile (%d)" % [pid + 1, _discard_view_cards.size()]
	discard_view_title.text = title
	discard_view_stacked.set_pressed_no_signal(false)
	discard_view_overlay.visible = true
	_refresh_discard_view_grid()


func _refresh_discard_view_grid() -> void:
	var stacked := discard_view_stacked.button_pressed

	for child in discard_view_grid.get_children():
		child.queue_free()

	if _discard_view_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No cards in discard pile."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		discard_view_grid.add_child(empty_label)
		return

	if stacked:
		var groups := _group_cards(_discard_view_cards)
		for group in groups:
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(group["card_data"])
			card.is_selectable = false
			card.drag_enabled = false
			_set_gallery_hover(card)
			discard_view_grid.add_child(card)
			_add_count_badge(card, group["count"])
	else:
		for card_data in _discard_view_cards:
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.is_selectable = false
			card.drag_enabled = false
			_set_gallery_hover(card)
			discard_view_grid.add_child(card)


func _on_discard_view_stacked_toggled(_value: bool) -> void:
	_refresh_discard_view_grid()


func _hide_discard_view() -> void:
	discard_view_overlay.visible = false
	for child in discard_view_grid.get_children():
		child.queue_free()
	_discard_view_cards.clear()


# --- Monster deck view UI ---

func _on_monster_deck_clicked(pid: int) -> void:
	# Only allow viewing your own monster deck
	if is_multiplayer_game and pid != local_player_id:
		return
	var player := _get_player_state(pid)
	_monster_deck_view_cards = player.monster_deck.duplicate(true)
	var title := "Monster Deck (%d)" % _monster_deck_view_cards.size()
	monster_deck_view_title.text = title
	monster_deck_view_stacked.set_pressed_no_signal(false)
	monster_deck_view_overlay.visible = true
	_refresh_monster_deck_view_grid()


func _refresh_monster_deck_view_grid() -> void:
	var stacked := monster_deck_view_stacked.button_pressed

	for child in monster_deck_view_grid.get_children():
		child.queue_free()

	if _monster_deck_view_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No cards remaining in monster deck."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		monster_deck_view_grid.add_child(empty_label)
		return

	if stacked:
		var groups := _group_cards(_monster_deck_view_cards)
		for group in groups:
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(group["card_data"])
			card.is_selectable = false
			card.drag_enabled = false
			_set_gallery_hover(card)
			monster_deck_view_grid.add_child(card)
			_add_count_badge(card, group["count"])
	else:
		for card_data in _monster_deck_view_cards:
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.is_selectable = false
			card.drag_enabled = false
			_set_gallery_hover(card)
			monster_deck_view_grid.add_child(card)


func _on_monster_deck_view_stacked_toggled(_value: bool) -> void:
	_refresh_monster_deck_view_grid()


func _hide_monster_deck_view() -> void:
	monster_deck_view_overlay.visible = false
	for child in monster_deck_view_grid.get_children():
		child.queue_free()
	_monster_deck_view_cards.clear()


# --- Zone stack view UI ---

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
	_zone_stack_view_cards.clear()
	if has_monster:
		_zone_stack_view_cards.append(player.current_monster)
		for m in player.monster_stack:
			_zone_stack_view_cards.append(m)
	for card_data in stack:
		_zone_stack_view_cards.append(card_data)
	var total: int = _zone_stack_view_cards.size()
	zone_stack_view_title.text = "Zone %d (%d card%s)" % [zone_num, total, "" if total == 1 else "s"]
	zone_stack_view_overlay.visible = true
	_refresh_zone_stack_view_grid()


func _refresh_zone_stack_view_grid() -> void:
	for child in zone_stack_view_grid.get_children():
		child.queue_free()

	for i in range(_zone_stack_view_cards.size()):
		var card_data: Dictionary = _zone_stack_view_cards[i]
		var card: Control = card_scene.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.is_selectable = false
		card.drag_enabled = false
		_set_gallery_hover(card)
		zone_stack_view_grid.add_child(card)


func _hide_zone_stack_view() -> void:
	zone_stack_view_overlay.visible = false
	for child in zone_stack_view_grid.get_children():
		child.queue_free()
	_zone_stack_view_cards.clear()


# --- Card zoom (right-click) UI ---

func _on_zone_slot_right_clicked(zone_num: int, pid: int) -> void:
	var player := _get_player_state(pid)
	var zone_idx: int = zone_num - 1
	if zone_idx < 0 or zone_idx >= 8:
		return
	# Show the monster card if this is the monster's zone, otherwise the top battle card
	var card_data: Dictionary = {}
	if not player.current_monster.is_empty() and (player.monster_zone - 1) == zone_idx:
		card_data = player.current_monster
	elif not player.is_zone_empty(zone_idx):
		card_data = player.get_zone_top_card(zone_idx)
	if card_data.is_empty():
		return
	_show_card_zoom(card_data)


func _on_strategy_slot_right_clicked(strategy_idx: int, pid: int) -> void:
	var player := _get_player_state(pid)
	if strategy_idx < 0 or strategy_idx >= player.strategy_zones.size():
		return
	var card_data: Dictionary = player.strategy_zones[strategy_idx]
	if card_data.is_empty():
		return
	_show_card_zoom(card_data)


func _on_hand_card_right_clicked(card: Control, hand_player_id: int) -> void:
	if hand_player_id != local_player_id:
		return
	if "card_data" in card and not card.card_data.is_empty():
		_show_card_zoom(card.card_data)


func _show_card_zoom(card_data: Dictionary) -> void:
	# Clear any existing zoomed card
	for child in card_zoom_container.get_children():
		child.queue_free()
	var card: Control = card_scene.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.is_selectable = false
	card.drag_enabled = false
	card.hover_scale = 1.0
	card.hover_lift = 0.0
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var is_strategy: bool = card_data.get("card_type") == CardEnums.CardType.STRATEGY
	if is_strategy:
		# Strategy card: portrait 300x420 rotated -90° to appear as landscape 420x300.
		# Use a wrapper sized to the landscape dimensions so CenterContainer centers correctly.
		var portrait_size := Vector2(300, 420)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(portrait_size.y, portrait_size.x) # 420x300
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_zoom_container.add_child(wrapper)
		card.custom_minimum_size = Vector2.ZERO
		card.size = portrait_size
		card.pivot_offset = portrait_size / 2.0
		card.rotation = deg_to_rad(-90)
		# Center the portrait card within the landscape wrapper
		card.position = Vector2(
			(wrapper.custom_minimum_size.x - portrait_size.x) / 2.0,
			(wrapper.custom_minimum_size.y - portrait_size.y) / 2.0
		)
		wrapper.add_child(card)
	else:
		card.custom_minimum_size = Vector2(300, 420)
		card_zoom_container.add_child(card)
	card_zoom_overlay.visible = true


func _on_overlay_background_clicked(event: InputEvent, hide_func: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_func.call()


func _on_card_zoom_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_card_zoom()


func _hide_card_zoom() -> void:
	card_zoom_overlay.visible = false
	for child in card_zoom_container.get_children():
		child.queue_free()


# --- Card hover preview ---

func _show_card_preview(data: Dictionary) -> void:
	if data.is_empty():
		return
	_preview_card.set_card_data_dict(data)
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


func _hide_card_preview() -> void:
	_preview_container.visible = false


func _on_log_meta_hover_started(meta: Variant) -> void:
	var card_id: String = str(meta)
	var data: Dictionary = CardData.get_card_by_id(card_id)
	if not data.is_empty():
		_show_card_preview(data)


func _on_log_meta_hover_ended(_meta: Variant) -> void:
	_hide_card_preview()


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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if "card_data" in card and not card.card_data.is_empty():
			_show_card_zoom(card.card_data)


func _get_card_template_id(card_data: Dictionary) -> String:
	## Extract the template card number from an instance ID.
	## Instance IDs: "EBP01-001_1_0" -> "EBP01-001", Monster IDs: "EBP01-001" -> "EBP01-001"
	var id: String = card_data.get("id", "")
	var parts := id.split("_")
	return parts[0] if not parts.is_empty() else id


func _group_cards(cards: Array[Dictionary]) -> Array[Dictionary]:
	## Group cards by template ID. Returns Array of {card_data, count, has_match}.
	var groups: Dictionary = {} # template_id -> {card_data, count, has_match}
	var order: Array[String] = [] # Preserve first-seen order
	for card_data in cards:
		var tid := _get_card_template_id(card_data)
		if groups.has(tid):
			groups[tid]["count"] += 1
			if _deck_search_matching_ids.has(card_data.get("id", "")):
				groups[tid]["has_match"] = true
		else:
			groups[tid] = {
				"card_data": card_data,
				"count": 1,
				"has_match": _deck_search_matching_ids.has(card_data.get("id", "")),
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
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.position = Vector2(4, 4)
	card.add_child(badge)


func _clear_grid(grid: GridContainer, click_handler: Callable) -> void:
	for child in grid.get_children():
		if "card_clicked" in child and child.card_clicked.is_connected(click_handler):
			child.card_clicked.disconnect(click_handler)
		child.queue_free()


func _resolve_deck_search_local(selected: Dictionary) -> void:
	if is_multiplayer_game and not NetworkManager.is_host():
		# Client sends selection back to host
		_rpc_deck_search_resolved.rpc_id(1, JSON.stringify(selected))
	else:
		turn_manager.action_handler.effect_handler.resolve_deck_search(selected)


# --- Multiplayer: State broadcast (host -> client) ---

func _broadcast_state() -> void:
	if not is_multiplayer_game or not NetworkManager.is_host():
		return
	if not turn_manager or not turn_manager.game_state:
		return

	for peer_id in NetworkManager.peer_player_map:
		if peer_id == 1:
			continue # Don't send to self (server peer ID is 1)
		var viewer_id: int = NetworkManager.peer_player_map[peer_id]
		var state_json := _serialize_game_state(viewer_id)
		_rpc_receive_state.rpc_id(peer_id, state_json)


func _serialize_game_state(viewer_id: int) -> String:
	var gs := turn_manager.game_state
	var eh := turn_manager.effect_handler
	var zone_cp_0: Array = eh.get_zone_cp_modifiers(0) if eh else []
	var zone_cp_1: Array = eh.get_zone_cp_modifiers(1) if eh else []
	var cp_total_0: int = 0
	var cp_total_1: int = 0
	for v in zone_cp_0: cp_total_0 += v
	for v in zone_cp_1: cp_total_1 += v
	var data := {
		"current_player_id": gs.current_player_id,
		"current_phase": int(gs.current_phase),
		"turn_number": gs.turn_number,
		"is_game_over": turn_manager.is_game_over,
		"players": [],
		"cp_modifiers": [cp_total_0, cp_total_1],
		"threat_modifiers": [eh.get_threat_level_modifier(0) if eh else 0, eh.get_threat_level_modifier(1) if eh else 0],
		"zone_cp_modifiers": [zone_cp_0, zone_cp_1],
	}
	for i in range(2):
		var pd := _serialize_player_state(gs.players[i])
		if i != viewer_id:
			# Strip hand and monster deck data for opponent — only send counts
			pd.erase("hand")
			pd.erase("monster_deck")
		data["players"].append(pd)
	return JSON.stringify(data)


func _serialize_player_state(ps: PlayerState) -> Dictionary:
	return {
		"player_id": ps.player_id,
		"monster_zone": ps.monster_zone,
		"rage": ps.rage,
		"current_monster": ps.current_monster,
		"zones": ps.zones.duplicate(true),
		"strategy_zones": ps.strategy_zones.duplicate(true),
		"hand": ps.hand.duplicate(true),
		"hand_count": ps.hand.size(),
		"main_deck_count": ps.main_deck.size(),
		"discard_pile": ps.discard_pile.duplicate(true),
		"discard_pile_count": ps.discard_pile.size(),
		"has_invaded_this_turn": ps.has_invaded_this_turn,
		"has_played_monster_this_turn": ps.has_played_monster_this_turn,
		"monster_stack": ps.monster_stack.duplicate(true),
		"burst_monster": ps.burst_monster,
		"pre_burst_monster": ps.pre_burst_monster,
		"monster_deck": ps.monster_deck.duplicate(true),
	}


func _compute_playable_data() -> Dictionary:
	var gs := turn_manager.game_state
	var player := gs.get_current_player()
	var opponent := gs.get_opponent_of_current()
	var rules := turn_manager.rules_engine
	var playable_battle := rules.get_playable_battle_cards(player, opponent)
	var battle_zones_per_card: Dictionary = {}
	for idx in playable_battle:
		var card: Dictionary = player.hand[idx]
		var card_id: String = card.get("id", "")
		if not card_id.is_empty():
			battle_zones_per_card[card_id] = rules.get_valid_zones_for_card(card, player, opponent)
	return {
		"valid_actions": rules.get_valid_actions(gs),
		"battle_cards": playable_battle,
		"battle_zones": battle_zones_per_card,
		"strategy_cards": rules.get_playable_strategy_cards(player),
		"monster_cards": rules.get_playable_monsters(player),
		"rage_cards": rules.get_monster_cards_for_rage(player),
		"invade_cards": rules.get_discardable_cards_for_invade(player),
	}


# --- Multiplayer RPCs ---

## Client -> Host: submit an action
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_action(action_type: int, params_json: String) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	if sender_player_id != turn_manager.game_state.current_player_id:
		return # Not their turn

	var action: CardEnums.ActionType = action_type as CardEnums.ActionType
	var params: Dictionary = {}
	if not params_json.is_empty():
		params = JSON.parse_string(params_json)
		# JSON parses ints as floats — convert known fields
		if params.has("hand_index"):
			params["hand_index"] = int(params["hand_index"])
		if params.has("zone_index"):
			params["zone_index"] = int(params["zone_index"])

	turn_manager.submit_action(action, params)


## Host -> Client: full game state update
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_state(state_json: String) -> void:
	var data: Dictionary = JSON.parse_string(state_json)
	if data.is_empty():
		return

	_client_current_player_id = int(data["current_player_id"])

	# Extract effect modifiers
	if data.has("cp_modifiers"):
		_client_cp_modifiers = data["cp_modifiers"]
		for j in range(_client_cp_modifiers.size()):
			_client_cp_modifiers[j] = int(_client_cp_modifiers[j])
	if data.has("threat_modifiers"):
		_client_threat_modifiers = data["threat_modifiers"]
		for j in range(_client_threat_modifiers.size()):
			_client_threat_modifiers[j] = int(_client_threat_modifiers[j])
	if data.has("zone_cp_modifiers"):
		_client_zone_cp_mods = data["zone_cp_modifiers"]
		for i in range(_client_zone_cp_mods.size()):
			var arr: Array = _client_zone_cp_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])

	# Reconstruct PlayerState objects
	var players_data: Array = data["players"]
	for i in range(2):
		var pd: Dictionary = players_data[i]
		_client_players[i] = _dict_to_player_state(pd, i == local_player_id)

	# Update UI
	phase_label.text = CardEnums.phase_to_string(int(data["current_phase"]) as CardEnums.GamePhase)
	turn_label.text = "Turn %d - Player %d" % [int(data["turn_number"]), int(data["current_player_id"]) + 1]
	_sync_boards()
	_update_hand_visibility(_client_current_player_id)


## Host -> Client: valid actions and playable indices
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_action_context(actions_json: String, playable_json: String) -> void:
	_action_pending = false
	# Clean up any stale discard/selection state before enabling action buttons
	if _discard_selecting:
		_force_cleanup_discard_selection()
	_cancel_selection()

	var actions: Array = JSON.parse_string(actions_json)
	_client_playable = JSON.parse_string(playable_json)
	# Store valid_actions in playable for _on_pass_pressed cancel path
	_client_playable["valid_actions"] = actions
	# Convert float arrays to int arrays
	for key in _client_playable:
		if _client_playable[key] is Array:
			var arr: Array = _client_playable[key]
			for j in range(arr.size()):
				if arr[j] is float:
					arr[j] = int(arr[j])
	_update_action_buttons(actions)


## Host -> Client: log message
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_log(text: String) -> void:
	if log_output:
		log_output.append_text(text + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)


## Host -> Client: deck search request (player must choose a card)
@rpc("authority", "call_remote", "reliable")
func _rpc_deck_search_requested(matching_json: String, all_json: String, prompt: String) -> void:
	var matching: Array = JSON.parse_string(matching_json)
	var all_cards: Array = JSON.parse_string(all_json)
	var typed_matching: Array[Dictionary] = []
	for c in matching:
		typed_matching.append(c)
	var typed_all: Array[Dictionary] = []
	for c in all_cards:
		typed_all.append(c)
	_show_deck_search(typed_matching, typed_all, prompt)


## Client -> Host: deck search resolved (player chose a card or skipped)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_resolved(selected_json: String) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return
	var selected: Dictionary = {}
	if not selected_json.is_empty():
		selected = JSON.parse_string(selected_json)
		if selected == null:
			selected = {}
	turn_manager.action_handler.effect_handler.resolve_deck_search(selected)


## Host -> Client: hand card selection request (player must choose a card from hand)
@rpc("authority", "call_remote", "reliable")
func _rpc_hand_card_selection_requested(indices_json: String, prompt: String, allow_skip: bool) -> void:
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(indices_json)
	var valid_indices: Array[int] = []
	for v in parsed:
		valid_indices.append(int(v))
	_show_hand_card_selection(local_player_id, valid_indices, prompt, allow_skip)


## Client -> Host: hand card selection resolved
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_resolved(hand_index: int) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return
	turn_manager.action_handler.effect_handler.resolve_hand_card_selection(hand_index)


## Host -> Client: hand discard request (player must choose cards to discard)
@rpc("authority", "call_remote", "reliable")
func _rpc_hand_discard_requested(discard_count: int) -> void:
	if NetworkManager.is_host():
		return # Safety: this RPC is only for clients
	_show_hand_discard_selection(local_player_id, discard_count)


## Client -> Host: hand discard resolved (player chose cards)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_resolved(indices_json: String) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return
	var parsed: Array = JSON.parse_string(indices_json)
	var hand_indices: Array[int] = []
	for v in parsed:
		hand_indices.append(int(v))
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	turn_manager.action_handler.effect_handler.resolve_hand_discard(sender_player_id, hand_indices)


## Host -> Client: zone target request (player must choose a zone)
@rpc("authority", "call_remote", "reliable")
func _rpc_zone_target_requested(target_player_id: int, zones_json: String, prompt: String, allow_skip: bool) -> void:
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(zones_json)
	var valid_zones: Array[int] = []
	for v in parsed:
		valid_zones.append(int(v))
	_show_zone_target_selection(local_player_id, target_player_id, valid_zones, prompt, allow_skip)


## Client -> Host: zone target resolved (player chose a zone)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_zone_target_resolved(zone_index: int) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return
	turn_manager.action_handler.effect_handler.resolve_zone_target(zone_index)


## Host -> Client: choice request (player must choose ability order)
@rpc("authority", "call_remote", "reliable")
func _rpc_choice_requested(options_json: String, prompt: String) -> void:
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(options_json)
	var options: Array[String] = []
	for v in parsed:
		options.append(str(v))
	_show_choice_selection(local_player_id, options, prompt)


## Client -> Host: choice resolved (player chose an option)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice_resolved(index: int) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return
	turn_manager.action_handler.effect_handler.resolve_choice(index)


## Host -> Client: highlight a zone card during effect resolution
@rpc("authority", "call_remote", "reliable")
func _rpc_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if NetworkManager.is_host():
		return
	_apply_zone_highlight(pid, zone_index, true)


## Host -> Client: unhighlight a zone card after effect resolution
@rpc("authority", "call_remote", "reliable")
func _rpc_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if NetworkManager.is_host():
		return
	_apply_zone_highlight(pid, zone_index, false)


## Host -> Client: highlight the source card of an active effect
@rpc("authority", "call_remote", "reliable")
func _rpc_effect_card_highlighted(pid: int, card_id: String) -> void:
	if NetworkManager.is_host():
		return
	_apply_card_highlight(pid, card_id, true)


## Host -> Client: unhighlight the source card after effect resolves
@rpc("authority", "call_remote", "reliable")
func _rpc_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if NetworkManager.is_host():
		return
	_apply_card_highlight(pid, card_id, false)


## Host -> Client: game over
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_game_ended(winner_id: int, reason: String) -> void:
	_action_pending = false
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Player %d Wins!\n%s" % [winner_id + 1, reason]
	_disable_all_buttons()


# --- Multiplayer: State deserialization (client) ---

func _dict_to_player_state(data: Dictionary, is_local: bool) -> PlayerState:
	var ps := PlayerState.new(int(data["player_id"]))
	ps.monster_zone = int(data["monster_zone"])
	ps.rage = int(data["rage"])
	ps.current_monster = data.get("current_monster", {})
	ps.has_invaded_this_turn = data.get("has_invaded_this_turn", false)
	ps.has_played_monster_this_turn = data.get("has_played_monster_this_turn", false)
	for m in data.get("monster_stack", []):
		ps.monster_stack.append(m)
	ps.burst_monster = data.get("burst_monster", {})
	ps.pre_burst_monster = data.get("pre_burst_monster", {})

	# Zones
	var zones_data: Array = data.get("zones", [])
	for i in range(mini(zones_data.size(), 8)):
		ps.zones[i] = zones_data[i]

	# Strategy zones
	var sz_data: Array = data.get("strategy_zones", [])
	for i in range(mini(sz_data.size(), 2)):
		ps.strategy_zones[i] = sz_data[i]

	# Hand: full data for local player, face-down placeholders for opponent
	if is_local and data.has("hand"):
		ps.hand.assign(data["hand"])
	else:
		var count: int = int(data.get("hand_count", 0))
		ps.hand.clear()
		for j in range(count):
			ps.hand.append({"face_down": true, "id": "opponent_%d" % j})

	# Monster deck: full data for local player, empty for opponent
	if is_local and data.has("monster_deck"):
		ps.monster_deck.assign(data["monster_deck"])

	# Deck/discard: only counts needed for display labels
	var deck_count: int = int(data.get("main_deck_count", 0))
	ps.main_deck.resize(deck_count)
	for j in range(deck_count):
		ps.main_deck[j] = {}

	if data.has("discard_pile"):
		ps.discard_pile.assign(data["discard_pile"])
	else:
		var discard_count: int = int(data.get("discard_pile_count", 0))
		ps.discard_pile.resize(discard_count)
		for j in range(discard_count):
			ps.discard_pile[j] = {}

	return ps


# --- Multiplayer: Disconnect handling ---

func _on_opponent_disconnected(_peer_id: int) -> void:
	_disable_all_buttons()
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Opponent disconnected."
	# The EndGamePanel should have a way to return to menu.
	# If it has a button, it will handle it. Otherwise we add a timer.
