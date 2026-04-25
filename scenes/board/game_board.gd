extends Control

## Main game controller. Orchestrates the UI, TurnManager, and both PlayerBoards.
## In multiplayer, the host runs TurnManager and broadcasts state to the client.
## The client receives state via RPC and sends actions back to the host.

var turn_manager: TurnManager # Only exists on host/solo
const CardScript := preload("res://scenes/cards/card.gd")
var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# Replay recording
var replay_recorder: ReplayRecorder
var _save_game_button: Button
var _loaded_from_save: bool = false

# Bot state
var bot_player: BotPlayer
var is_bot_game: bool = false
var _bot_seed_was_explicit: bool = false
var _bot_cards_visible: bool = false
var _bot_visibility_button: Button

# Multiplayer state
var is_multiplayer_game: bool = false
var local_player_id: int = 0 # 0 for host/solo, 1 for client

# Client-side state (populated from host RPCs)
var _client_players: Array[PlayerState] = []
var _client_current_player_id: int = 0
var _client_turn_number: int = 0
var _client_phase: CardEnums.GamePhase = CardEnums.GamePhase.START
var _client_playable: Dictionary = {} # Playable card/zone indices from host
var _client_cp_modifiers: Array = [0, 0]
var _client_threat_modifiers: Array = [0, 0]
var _client_zone_cp_mods: Array = [[], []]
var _client_strategy_cp_mods: Array = [[], []]
var _client_zone_rank_mods: Array = [[], []]
var _client_monster_cp_mods: Array = [0, 0]
var _client_gradients_applied: bool = false
# Client-side stats snapshot (synced from host for disconnect reporting)
var _client_stats_elapsed_ms: Array[int] = [0, 0]
var _client_stats_game_start_ms: int = 0
var _client_stats_turn_start_ms: int = 0
var _client_stats_opponent_hand: Array = []
var _client_stats_deck_names: Array[String] = ["", ""]
var _client_stats_decklists: Array = [null, null]

# UI references
@onready var player1_board: Control = $VBoxContainer/BoardArea/BoardColumn/Player1Board
@onready var player2_board: Control = $VBoxContainer/BoardArea/BoardColumn/Player2Board
@onready var action_panel: Control = $ActionPanel
@onready var log_output: RichTextLabel = $LogPanel/LogVBox/LogOutput
@onready var chat_input: LineEdit = $LogPanel/LogVBox/ChatRow/ChatInput
@onready var chat_char_count: Label = $LogPanel/LogVBox/ChatRow/CharCount
## Log entries are Dictionaries (tokens rendered by GameLog.render) or Strings
## (legacy/system messages that render as-is). See `_on_log_message`.
var _log_tokens: Array = []
var _pending_log_tokens: Array = [] # Buffered for next broadcast
var _pending_sound_events: PackedStringArray = [] # Sound events buffered for client
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
@onready var deck_search_overlay: Control = $DeckSearchOverlay
@onready var deck_search_prompt: Label = $DeckSearchOverlay/DeckSearchPanel/VBox/PromptLabel
@onready var deck_search_grid: GridContainer = $DeckSearchOverlay/DeckSearchPanel/VBox/ScrollContainer/CardGrid
@onready var deck_search_skip: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/SkipButton
@onready var deck_search_show_all: CheckButton = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/ShowAllToggle
@onready var deck_search_stacked: CheckButton = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/StackedToggle
@onready var deck_search_view_board: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/ToggleRow/ViewBoardButton
@onready var show_cards_button: Button = $ShowCardsButton
@onready var hand_toggle_button: Button = $HandButtonStack/HandToggleButton
@onready var sort_hand_button: Button = $HandButtonStack/SortHandButton
@onready var opponent_hand_button_stack: HBoxContainer = $OpponentHandButtonStack
@onready var opponent_hand_toggle_button: Button = $OpponentHandButtonStack/OpponentHandToggleButton
@onready var opponent_sort_hand_button: Button = $OpponentHandButtonStack/OpponentSortHandButton

# Deck arrange overlay UI references
@onready var deck_arrange_overlay: Control = $DeckArrangeOverlay
@onready var deck_arrange_prompt: Label = $DeckArrangeOverlay/DeckArrangePanel/VBox/PromptLabel
@onready var deck_arrange_keep_panel: PanelContainer = $DeckArrangeOverlay/DeckArrangePanel/VBox/ArrangeContainer/KeepPanel
@onready var deck_arrange_keep_cards: GridContainer = $DeckArrangeOverlay/DeckArrangePanel/VBox/ArrangeContainer/KeepPanel/KeepVBox/KeepCards
@onready var deck_arrange_discard_panel: PanelContainer = $DeckArrangeOverlay/DeckArrangePanel/VBox/ArrangeContainer/DiscardPanel
@onready var deck_arrange_discard_cards: GridContainer = $DeckArrangeOverlay/DeckArrangePanel/VBox/ArrangeContainer/DiscardPanel/DiscardVBox/DiscardCards
@onready var deck_arrange_view_board: Button = $DeckArrangeOverlay/DeckArrangePanel/VBox/ButtonRow/ViewBoardButton
@onready var deck_arrange_confirm: Button = $DeckArrangeOverlay/DeckArrangePanel/VBox/ButtonRow/ConfirmButton

# Card select overlay UI references
@onready var card_pool_select_overlay: Control = $CardSelectOverlay
@onready var card_pool_select_prompt: Label = $CardSelectOverlay/CardSelectPanel/VBox/PromptLabel
@onready var card_pool_select_pool_grid: GridContainer = $CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/PoolPanel/PoolVBox/ScrollContainer/PoolGrid
@onready var card_pool_select_selection_grid: GridContainer = $CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/ScrollContainer/SelectionGrid
@onready var card_pool_select_selection_label: Label = $CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/SelectionLabel
@onready var card_pool_select_show_all: CheckButton = $CardSelectOverlay/CardSelectPanel/VBox/ToggleRow/ShowAllToggle
@onready var card_pool_select_stacked: CheckButton = $CardSelectOverlay/CardSelectPanel/VBox/ToggleRow/StackedToggle
@onready var card_pool_select_view_board: Button = $CardSelectOverlay/CardSelectPanel/VBox/ToggleRow/ViewBoardButton
@onready var card_pool_select_skip: Button = $CardSelectOverlay/CardSelectPanel/VBox/ButtonRow/SkipButton
@onready var card_pool_select_confirm: Button = $CardSelectOverlay/CardSelectPanel/VBox/ButtonRow/ConfirmButton

# Discard view UI references
@onready var discard_view_overlay: Control = $DiscardViewOverlay
@onready var discard_view_title: Label = $DiscardViewOverlay/DiscardViewPanel/VBox/TitleLabel
@onready var discard_view_grid: GridContainer = $DiscardViewOverlay/DiscardViewPanel/VBox/ScrollContainer/CardGrid
@onready var discard_view_close: Button = $DiscardViewOverlay/DiscardViewPanel/VBox/CloseButton
@onready var discard_view_stacked: CheckButton = $DiscardViewOverlay/DiscardViewPanel/VBox/StackedToggle

# In-game stacked preference (initialized from GameSettings, remembered for the match)
var _match_stacked_view: bool = true

# Stored deck search data for toggling between matching/all/stacked
var _deck_search_matching: Array[Dictionary] = []
var _deck_search_all: Array[Dictionary] = []
var _deck_search_matching_ids: Dictionary = {} # card id -> true, for highlighting

# Stored discard view data for stacked toggle
var _discard_view_cards: Array[Dictionary] = []

# Deck arrange data
var _arrange_keep: Array[Dictionary] = []
var _arrange_discard: Array[Dictionary] = []
var _arrange_dragging_card: Control = null
var _arrange_drag_source: String = "" # "keep" or "discard"
var _arrange_drag_index: int = -1

# Card select data
var _card_select_matching: Array[Dictionary] = []
var _card_select_all: Array[Dictionary] = []
var _card_select_matching_ids: Dictionary = {} # card id -> true
var _card_select_selected: Array[Dictionary] = []
var _card_select_min_count: int = 0
var _card_select_max_count: int = 0
var _arrange_drop_indicator: ColorRect = null
var _view_board_source_overlay: Control = null

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

# Pinch-to-zoom / pan state for card zoom overlay (touch only)
var _pinch_active: bool = false
var _pinch_used: bool = false # True after any pinch — suppress dismiss until next fresh tap
var _pinch_start_distance: float = 0.0
var _pinch_start_scale: float = 1.0
var _pinch_touches: Dictionary = {} # index → position
var _zoom_shown_frame: int = -1 # Frame when overlay was shown (ignore dismiss for 2 frames)
var _zoom_dragging: bool = false # Single-finger drag active
var _zoom_drag_start: Vector2 = Vector2.ZERO # Touch start position for deadzone check
const PINCH_MAX_SCALE: float = 3.0
const ZOOM_DRAG_DEADZONE: float = 20.0

# Turn tracker: main phase labels [player_id][phase_index]
@onready var _turn_tracker_phases: Array = [
	[ # Player 1
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1Start,
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1Main,
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1Counter,
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1End,
	],
	[ # Player 2
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2Start,
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2Main,
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2Counter,
		$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2End,
	],
]
# Turn tracker: sub-phase labels [player_id][phase_index] -> Array of Labels
@onready var _turn_tracker_subs: Array = [
	[ # Player 1
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1StartEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1StartDraw,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1StartDiscard,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1StartReset],
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1MainEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1MainActions],
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1CounterEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1CounterCheck],
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1EndEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1EndAdvance,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1EndRefill],
	],
	[ # Player 2
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2StartEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2StartDraw,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2StartDiscard,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2StartReset],
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2MainEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2MainActions],
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2CounterEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2CounterCheck],
		[$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2EndEffects,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2EndAdvance,
		 $VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2EndRefill],
	],
]
@onready var _turn_tracker_headers: Array = [
	$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P1Header,
	$VBoxContainer/BoardArea/RightSpacer/TurnTracker/P2Header,
]
@onready var _turn_label: Label = $VBoxContainer/BoardArea/RightSpacer/TurnLabelMargin/TurnLabel

# Card hover preview
var _preview_container: Control
var _preview_bg: Panel
var _preview_card: Control

# Stored zone stack view data
var _zone_stack_view_cards: Array[Dictionary] = []
var _cards_revealed_active: bool = false

# State tracking
var pending_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var waiting_for_card_select: bool = false
var waiting_for_zone_select: bool = false
var selected_card_id: String = ""
var _selected_card_data: Dictionary = {} # Card data dict for the selected card
var _awaiting_confirmation: bool = false
var _confirming_pass: bool = false
var _leave_dialog: ConfirmationDialog = null

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

# State versioning for desync detection
var _state_version: int = 0 # Incremented on each broadcast (host only)
var _client_state_version: int = 0 # Last received version (client only)
var _broadcast_pending: bool = false # Debounce flag for frame-based coalescing
var _last_sent_state: Dictionary = {} # Host: last serialized state sent to client
var _last_sent_version: int = 0 # Host: version of _last_sent_state
var _client_full_state: Dictionary = {} # Client: accumulated full state from deltas
var _last_resync_request_ms: int = 0 # Client: rate-limit resync requests

# Zone target selection state (for effects that let the player pick a zone)
var _zone_target_selecting: bool = false
var _zone_target_player_id: int = -1 # Who is choosing
var _zone_target_board_pid: int = -1 # Whose board the zones are on
var _zone_target_valid_zones: Array[int] = []
var _zone_target_allow_skip: bool = false

# Strategy target selection state (for effects that let the player pick a strategy zone)
var _strategy_target_selecting: bool = false
var _strategy_target_player_id: int = -1
var _strategy_target_board_pid: int = -1
var _strategy_target_valid_indices: Array[int] = []

# First-player choice state
var _first_player_choosing: bool = false
var _first_player_chooser_id: int = -1 # Player who gets to decide
var _first_player_result: int = -1 # Resolved first player id (-1 = pending)
var _first_player_id: int = 0 # Which player went first (for * indicator)

# Rematch state
var _rematch_requested: bool = false
var _opponent_rematch_requested: bool = false
var _game_ended_by_disconnect: bool = false
var _rematch_deck_select: VBoxContainer = null
var _rematch_deck_changed: bool = false
var _rematch_deck_name: String = ""

# Reconnect state
var _reconnect_cumulative_seconds: float = 0.0 # Cumulative across all disconnects
var _reconnect_current_start_ms: int = 0
var _waiting_for_reconnect: bool = false
var _reconnect_attempting: bool = false # Guard for client reconnect loop
const RECONNECT_CLAIM_WIN_SECONDS: float = 10.0
var _pending_interaction: Dictionary = {} # {method: String, args: Array}
# Reconnect overlay nodes (built in code)
var _reconnect_overlay: ColorRect = null
var _reconnect_label: Label = null
var _reconnect_timer_label: Label = null
var _reconnect_claim_btn: Button = null
var _reconnect_menu_btn: Button = null

# Stats time tracking
var _player_elapsed_ms: Array[int] = [0, 0]
var _turn_start_time_ms: int = 0
var _game_start_time_ms: int = 0
var _stats_uploaded: bool = false

# Standby choice selection state (for choosing ability resolution order)
var _choice_selecting: bool = false
var _choice_player_id: int = -1
var _choice_buttons: Array[Button] = []
var _choice_container: VBoxContainer = null
var _choice_panel: PanelContainer = null # Mobile wrapper panel

# Monster rank-up selection state
var _rankup_selecting: bool = false
var _rankup_player_id: int = -1
var _rankup_valid_indices: Array[int] = []

# Drag-to-zone state
var _drag_card: Control = null
var _drag_valid_zones: Array[int] = []
var _zone_select_valid: Array[int] = []
var _drag_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var _drag_can_rage: bool = false
var _drag_can_invade: bool = false
var _snap_preview_slot = null # Slot or Control currently being snap-previewed
var _highlighted_card: Control = null # Card with selection highlight border

# Turn tracker sub-phase index
var _current_sub_phase: int = 0

# Turn tracker transition queue (delays between phase changes)
const PHASE_TRANSITION_DELAY: float = 0.0
var _tracker_queue: Array[Dictionary] = []
var _tracker_draining: bool = false
var _tracker_last_phase: int = -1
var _tracker_last_player: int = -1

# Hand expand toggle
var _hand_expanded: bool = false
var _hand_tween: Tween = null
const HAND_EXPAND_OFFSET: float = 160.0

# Opponent hand expand toggle (solo only)
var _opponent_hand_expanded: bool = false
var _opponent_hand_tween: Tween = null
const OPPONENT_HAND_EXPAND_OFFSET: float = 195.0

# Mobile layout
var _is_mobile_layout: bool = false
var _mobile_phase_label: Label = null
var _mobile_log_tray_open: bool = false
var _mobile_log_toggle_btn: Button = null
var _mobile_log_tween: Tween = null
# FAB (Floating Action Button) system for mobile action buttons
var _fab_main_btn: Button = null
var _fab_backdrop: ColorRect = null
var _fab_container: Control = null
var _fab_expanded: bool = false
var _fab_action_btns: Array[Button] = []
var _fab_labels: Array[Label] = []
var _fab_tween: Tween = null
var _mobile_log_badge: Label = null
var _mobile_log_unread: int = 0
enum MobileBoardView {LOCAL_ENLARGED, OPPONENT_ENLARGED, BALANCED}
var _mobile_board_view: int = MobileBoardView.LOCAL_ENLARGED
var _mobile_view_toggle_btn: Button = null
var _mobile_tracker_tray_open: bool = false
var _mobile_tracker_toggle_btn: Button = null
var _mobile_tracker_tween: Tween = null
var _mobile_cp_tray_open: bool = false
var _mobile_cp_toggle_btn: Button = null
var _mobile_cp_tween: Tween = null
var _mobile_cp_panel: PanelContainer = null
var _mobile_cp_panel_w: float = 180.0
var _mobile_cp_opp_cp_label: Label = null
var _mobile_cp_opp_threat_label: Label = null
var _mobile_cp_local_cp_label: Label = null
var _mobile_cp_local_threat_label: Label = null
var _mobile_menu_btn: Button = null
var _mobile_menu_panel: Control = null
var _mobile_menu_backdrop: ColorRect = null
var _mobile_menu_open: bool = false
var _mobile_sound_button: Button = null
var _mobile_music_button: Button = null
# Safe area insets in canvas units (set in _apply_safe_area_insets)
var _safe_left: float = 0.0
var _safe_right: float = 0.0
var _safe_top: float = 0.0
var _safe_bottom: float = 0.0


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


func _build_reconnect_overlay() -> void:
	_reconnect_overlay = ColorRect.new()
	_reconnect_overlay.color = Color(0, 0, 0, 0.75)
	_reconnect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reconnect_overlay.z_index = 200
	_reconnect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_reconnect_overlay.visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH

	_reconnect_label = Label.new()
	_reconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reconnect_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_reconnect_label)

	_reconnect_timer_label = Label.new()
	_reconnect_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reconnect_timer_label.add_theme_font_size_override("font_size", 20)
	_reconnect_timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_reconnect_timer_label)

	_reconnect_claim_btn = Button.new()
	_reconnect_claim_btn.text = tr("STR_GB_CLAIM_WIN")
	_reconnect_claim_btn.custom_minimum_size = Vector2(200, 45)
	_reconnect_claim_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reconnect_claim_btn.add_theme_font_size_override("font_size", 20)
	_reconnect_claim_btn.visible = false
	_reconnect_claim_btn.pressed.connect(_on_reconnect_claim_win)
	vbox.add_child(_reconnect_claim_btn)

	_reconnect_menu_btn = Button.new()
	_reconnect_menu_btn.text = tr("STR_GB_RETURN_TO_MENU")
	_reconnect_menu_btn.custom_minimum_size = Vector2(200, 45)
	_reconnect_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reconnect_menu_btn.add_theme_font_size_override("font_size", 20)
	_reconnect_menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(_reconnect_menu_btn)

	_reconnect_overlay.add_child(vbox)
	add_child(_reconnect_overlay)


func _ready() -> void:
	# Free deck-builder texture cache to reclaim memory for gameplay
	CardScript.clear_texture_cache()

	is_multiplayer_game = NetworkManager.is_multiplayer()
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	local_player_id = NetworkManager.get_local_player_id() if is_multiplayer_game else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
	_match_stacked_view = _match_stacked_view

	# Wire hand CardManagers to PlayerBoards
	player1_board.hand_manager = player1_hand
	player2_board.hand_manager = player2_hand

	# Rearrange layout for client so local player sees their board at bottom
	_arrange_for_local_player()

	# Make turn tracker labels clickable to toggle auto settings
	_setup_settings_toggles()

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

		# Host / solo: create and run TurnManager
		turn_manager = TurnManager.new()
		if not GameSerializer.pending_load.is_empty():
			turn_manager.setup_from_save(GameSerializer.pending_load)
			_loaded_from_save = true
			_first_player_id = GameSerializer.pending_load.get("first_player_id", 0)
			GameSerializer.pending_load = {}
		else:
			turn_manager.setup(CardData)

		# Set player names from settings
		turn_manager.game_state.player_names[local_player_id] = GameSettings.player_name
		GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)
		for i in range(2):
			if i < _turn_tracker_headers.size():
				_turn_tracker_headers[i].text = GameLog.player_name(i)

		# Connect turn manager signals
		turn_manager.phase_started.connect(_on_phase_started)
		turn_manager.phase_ended.connect(_on_phase_ended)
		turn_manager.sub_phase_changed.connect(_on_sub_phase_changed)
		turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		turn_manager.turn_started.connect(_on_turn_started)
		turn_manager.game_ended.connect(_on_game_ended)
		turn_manager.log_message.connect(_on_log_message)
		turn_manager.confirmation_requested.connect(_on_confirmation_requested)

		# Connect action handler signals for visual feedback
		turn_manager.action_handler.cards_drawn.connect(_on_cards_drawn)
		turn_manager.action_handler.card_discarded.connect(_on_card_discarded)
		turn_manager.action_handler.rage_gained.connect(_on_rage_gained)
		turn_manager.action_handler.strategy_card_played.connect(_on_strategy_card_played)
		turn_manager.action_handler.battle_card_played.connect(_on_battle_card_played)
		turn_manager.action_handler.monster_advanced.connect(_on_monster_advanced)
		turn_manager.action_handler.battle_card_crushed.connect(_on_battle_card_crushed)
		turn_manager.action_handler.counter_succeeded.connect(_on_counter_succeeded)
		turn_manager.action_handler.play_cancelled.connect(_on_play_cancelled)
		turn_manager.action_handler.counter_failed.connect(_on_counter_failed)
		turn_manager.action_handler.counter_immunity_triggered.connect(_on_counter_immunity_triggered)
		turn_manager.action_handler.monster_countered.connect(_on_monster_countered)
		turn_manager.action_handler.monster_rankup_requested.connect(_on_monster_rankup_requested)

		# Connect effect handler signals for player choice UIs
		turn_manager.action_handler.effect_handler.deck_search_requested.connect(_on_deck_search_requested)
		turn_manager.action_handler.effect_handler.deck_arrange_requested.connect(_on_deck_arrange_requested)
		turn_manager.action_handler.effect_handler.card_select_requested.connect(_on_card_select_requested)
		turn_manager.action_handler.effect_handler.hand_discard_requested.connect(_on_hand_discard_requested)
		turn_manager.action_handler.effect_handler.hand_card_selection_requested.connect(_on_hand_card_selection_requested)
		turn_manager.action_handler.effect_handler.zone_target_requested.connect(_on_zone_target_requested)
		turn_manager.action_handler.effect_handler.strategy_target_requested.connect(_on_strategy_target_requested)
		turn_manager.action_handler.effect_handler.effect_zone_highlighted.connect(_on_effect_zone_highlighted)
		turn_manager.action_handler.effect_handler.effect_zone_unhighlighted.connect(_on_effect_zone_unhighlighted)
		turn_manager.action_handler.effect_handler.effect_card_highlighted.connect(_on_effect_card_highlighted)
		turn_manager.action_handler.effect_handler.effect_card_unhighlighted.connect(_on_effect_card_unhighlighted)
		turn_manager.action_handler.effect_handler.choice_requested.connect(_on_choice_requested)
		turn_manager.action_handler.effect_handler.cards_revealed_requested.connect(_on_cards_revealed_requested)
		turn_manager.action_handler.effect_handler.log_message.connect(_on_log_message)
		turn_manager.action_handler.effect_handler.card_evolved.connect(_on_card_evolved)
		turn_manager.action_handler.effect_handler.card_destroyed.connect(_on_card_destroyed)

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
			player.discard_reshuffled.connect(_on_discard_reshuffled)
	else:
		# Client: initialize empty client state, wait for host RPCs
		_client_players = [PlayerState.new(0), PlayerState.new(1)]
		GameLog.player_names[local_player_id] = GameSettings.player_name
		# If this is a reconnect (is_in_game was set before scene load), the host
		# already sent state before this scene existed — request a fresh broadcast.
		if NetworkManager.is_in_game:
			_rpc_request_resync.rpc_id(NetworkManager.host_peer_id)
			RpcLogger.log_send("send_player_name", GameSettings.player_name.length())
			_rpc_send_player_name.rpc_id(NetworkManager.host_peer_id, GameSettings.player_name)

	# Connect buttons
	btn_play_battle.pressed.connect(_on_play_battle_pressed)
	btn_play_strategy.pressed.connect(_on_play_strategy_pressed)
	btn_gain_rage.pressed.connect(_on_gain_rage_pressed)
	btn_play_monster.pressed.connect(_on_play_monster_pressed)
	btn_invade.pressed.connect(_on_invade_pressed)
	btn_end_main.pressed.connect(_on_end_main_pressed)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	btn_confirm.pressed.connect(_on_confirm_pressed)
	btn_bug_report.pressed.connect(_on_bug_report_pressed)
	btn_concede.pressed.connect(_on_concede_pressed)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)
	btn_sound_toggle.gui_input.connect(_on_sound_gui_input)
	btn_music_toggle.gui_input.connect(_on_music_gui_input)
	_update_sound_button_text()
	_update_music_button_text()
	btn_rematch.pressed.connect(_on_rematch_pressed)
	btn_end_menu.pressed.connect(_on_main_menu_pressed)

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
		NetworkManager.player_reconnected.connect(_on_opponent_reconnected)
		NetworkManager.is_in_game = true
		_build_reconnect_overlay()
		# Save reconnect session for app-restart recovery (online only)
		if NetworkManager.mode in [NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT]:
			GameSettings.save_reconnect_session(
				NetworkManager.get_game_code(),
				NetworkManager.is_host(),
				NetworkManager.game_mode,
				NetworkManager.is_public_room,
			)

	# Connect deck search buttons
	deck_search_skip.pressed.connect(_on_deck_search_skip)
	deck_search_show_all.toggled.connect(_on_deck_search_toggled)
	deck_search_stacked.toggled.connect(_on_deck_search_toggled)
	deck_search_view_board.pressed.connect(_on_deck_search_view_board)
	deck_arrange_view_board.pressed.connect(_on_deck_arrange_view_board)
	deck_arrange_confirm.pressed.connect(_on_deck_arrange_confirm)
	card_pool_select_skip.pressed.connect(_on_card_pool_select_skip)
	card_pool_select_confirm.pressed.connect(_on_card_pool_select_confirm)
	card_pool_select_show_all.toggled.connect(_on_card_select_toggled)
	card_pool_select_stacked.toggled.connect(_on_card_select_toggled)
	card_pool_select_view_board.pressed.connect(_on_card_pool_select_view_board)
	show_cards_button.pressed.connect(_on_show_cards_pressed)
	hand_toggle_button.pressed.connect(_on_hand_toggle_pressed)
	sort_hand_button.pressed.connect(_on_sort_hand_pressed)
	opponent_hand_toggle_button.pressed.connect(_on_opponent_hand_toggle_pressed)
	opponent_sort_hand_button.pressed.connect(_on_opponent_sort_hand_pressed)
	opponent_hand_button_stack.visible = not is_multiplayer_game

	# Bot card visibility toggle
	if is_bot_game:
		_setup_bot_visibility_toggle()

	# Save game button (solo/bot only)
	if not is_multiplayer_game:
		_setup_save_button()

	_setup_rematch_deck_select()

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
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input.text_changed.connect(_on_chat_text_changed)

	# Hide overlays and prompts
	end_game_panel.visible = false
	action_prompt_panel.visible = false
	deck_search_overlay.visible = false
	card_pool_select_overlay.visible = false
	show_cards_button.visible = false
	discard_view_overlay.visible = false
	monster_deck_view_overlay.visible = false
	zone_stack_view_overlay.visible = false
	card_zoom_overlay.visible = false

	# Ensure overlays render above hand cards (which have incrementing z_index)
	card_zoom_overlay.z_index = 200
	deck_search_overlay.z_index = 100
	deck_arrange_overlay.z_index = 100
	card_pool_select_overlay.z_index = 100
	discard_view_overlay.z_index = 100
	monster_deck_view_overlay.z_index = 100
	zone_stack_view_overlay.z_index = 100
	end_game_panel.z_index = 100

	# Leave game confirmation dialog
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = "Leave Game"
	_leave_dialog.dialog_text = "Leave the current game?"
	_leave_dialog.ok_button_text = "Leave"
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


# Per-player auto settings (initialized from GameSettings, toggled independently)
var _player_settings: Array[Dictionary] = []
var _setting_labels: Dictionary = {} # setting_name -> Array[Label]

const _SETTING_KEYS: Array[String] = [
	"auto_draw", "auto_phase_advance", "auto_discard_strategies",
	"auto_reset_rage", "auto_counter_check", "auto_advance",
	"confirm_main_phase_pass",
]


func _setup_settings_toggles() -> void:
	# Initialize per-player settings from GameSettings defaults
	for pid in range(2):
		var d := {}
		for key in _SETTING_KEYS:
			d[key] = GameSettings.get(key)
		_player_settings.append(d)

	# Sub-phase label → setting mappings: [phase_idx, sub_idx, setting_name]
	var mappings: Array[Array] = [
		[0, 1, "auto_draw"], # Start > Draw Cards
		[0, 2, "auto_discard_strategies"], # Start > Discard Strategies
		[0, 3, "auto_reset_rage"], # Start > Reset Rage
		[1, 1, "confirm_main_phase_pass"], # Main > Player Actions
		[2, 1, "auto_counter_check"], # Counter > Counter Check
		[3, 1, "auto_advance"], # End > Advance
		[3, 2, "auto_draw"], # End > Refill Hand
	]

	for pid in range(2):
		# In multiplayer, only make the local player's labels clickable
		if is_multiplayer_game and pid != local_player_id:
			continue
		for m in mappings:
			_wire_setting_label(_turn_tracker_subs[pid][m[0]][m[1]], m[2], pid)
		for i in range(4):
			_wire_setting_label(_turn_tracker_phases[pid][i], "auto_phase_advance", pid)

	_update_all_setting_indicators()


func _wire_setting_label(label: Label, setting: String, pid: int) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.set_meta("setting", setting)
	label.set_meta("player_id", pid)
	label.set_meta("base_text", label.text)
	label.gui_input.connect(_on_setting_label_input.bind(label))
	if not _setting_labels.has(setting):
		_setting_labels[setting] = []
	_setting_labels[setting].append(label)


func _on_setting_label_input(event: InputEvent, label: Label) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var setting: String = label.get_meta("setting")
		var pid: int = label.get_meta("player_id")
		_player_settings[pid][setting] = not _player_settings[pid][setting]
		_update_all_setting_indicators()
		# Re-apply turn tracker so phase label indicators refresh immediately
		if _tracker_last_phase >= 0:
			_apply_turn_tracker(_tracker_last_player, _tracker_last_phase as CardEnums.GamePhase, _current_sub_phase)


func _is_setting_auto(setting: String, pid: int) -> bool:
	# For most settings, true = auto. For confirm_main_phase_pass, true = manual.
	if _player_settings.is_empty():
		return setting != "confirm_main_phase_pass"
	var value: bool = _player_settings[pid].get(setting, false)
	if setting == "confirm_main_phase_pass":
		return not value
	return value


func _update_all_setting_indicators() -> void:
	for setting in _setting_labels:
		for label in _setting_labels[setting]:
			var pid: int = label.get_meta("player_id")
			if label in _turn_tracker_phases[0] or label in _turn_tracker_phases[1]:
				continue # Phase labels are updated in _apply_turn_tracker
			var base: String = label.get_meta("base_text")
			# `base` is captured from .tscn (raw STR_* key). The auto branch can
			# assign it back as-is and let Godot auto-translate at render time.
			# The manual branch composes a new string ("● " + …) that's not a
			# known translation key, so we must resolve it ourselves first.
			if not _is_setting_auto(setting, pid):
				var resolved := tr(base)
				var stripped := resolved.strip_edges(true, false)
				var indent_len := resolved.length() - stripped.length()
				label.text = resolved.left(maxi(indent_len - 2, 0)) + "● " + stripped
				label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			else:
				label.text = base
				label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT


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
		_first_player_chooser_id = 0
		_first_player_result = -1
		_first_player_choosing = true
		SfxManager.play("game_start")
		_show_first_player_choice()

		while _first_player_result < 0:
			await Engine.get_main_loop().process_frame

		_first_player_choosing = false
		_cleanup_first_player_ui()
		_first_player_id = _first_player_result
		_apply_gradients_and_sync()
		SfxManager.play("game_setup")
		turn_manager.start_game(_first_player_result)
		return

	if not is_multiplayer_game:
		# Solo: no need to choose, player 1 always goes first
		_first_player_id = 0
		_apply_gradients_and_sync()
		SfxManager.play("game_setup")
		turn_manager.start_game(0)
		return

	# Multiplayer: randomly select which player gets to choose who goes first
	_first_player_chooser_id = randi() % 2
	_first_player_result = -1
	_first_player_choosing = true

	_on_log_message(GameLog.coin_flip_won(_first_player_chooser_id))

	if _first_player_chooser_id != local_player_id:
		# The chooser is the remote client — send RPC, show waiting state locally
		_show_first_player_waiting()
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == _first_player_chooser_id:
				RpcLogger.log_send("first_player_choice_requested", 0)
				_rpc_first_player_choice_requested.rpc_id(peer_id)
	else:
		# Host is the chooser — tell the client to wait
		_show_first_player_choice()
		RpcLogger.log_send("first_player_waiting", 0)
		_rpc_first_player_waiting.rpc()

	# Wait for the choice to resolve
	while _first_player_result < 0:
		await Engine.get_main_loop().process_frame

	_first_player_choosing = false
	_cleanup_first_player_ui()
	# Tell the client to restore its action panel (waiting client never gets cleanup)
	RpcLogger.log_send("cleanup_first_player", 0)
	_rpc_cleanup_first_player.rpc()
	_apply_gradients_and_sync()
	_first_player_id = _first_player_result
	_on_log_message(GameLog.first_player_chose(_first_player_result, true))
	SfxManager.play("game_start")
	turn_manager.start_game(_first_player_result)


func _setup_replay_recorder() -> void:
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
	bot_player = BotPlayer.new()
	bot_player.config = NetworkManager.bot_config
	bot_player.bot_player_id = 1
	bot_player.game_state = turn_manager.game_state
	bot_player.rules_engine = turn_manager.rules_engine
	bot_player.turn_manager = turn_manager
	bot_player.action_handler = turn_manager.action_handler
	bot_player.effect_handler = turn_manager.action_handler.effect_handler
	bot_player.scene_tree = get_tree()

	# Connect bot to all decision signals
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

	# Analyze deck to determine playstyle
	bot_player.analyze_deck()

	# Set bot player name
	turn_manager.game_state.player_names[1] = "Bot"
	GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)
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


func _show_first_player_waiting() -> void:
	_disable_all_buttons()
	btn_concede.disabled = true
	_set_action_buttons_visible(false)
	card_select_prompt.text = tr("STR_GB_COIN_FLIP_WAITING")
	action_prompt_panel.visible = true


func _cleanup_first_player_ui() -> void:
	var container := action_panel.get_node_or_null("FirstPlayerContainer")
	if not container:
		container = get_node_or_null("FirstPlayerContainer")
	if container:
		container.queue_free()
	action_prompt_panel.visible = false
	_set_action_buttons_visible(true)
	btn_concede.disabled = false


func _show_first_player_choice() -> void:
	_disable_all_buttons()
	btn_concede.disabled = true
	_set_action_buttons_visible(false)
	card_select_prompt.text = tr("STR_GB_COIN_FLIP_WON")
	action_prompt_panel.visible = true

	var container := VBoxContainer.new()
	container.name = "FirstPlayerContainer"
	if _is_mobile_layout:
		container.anchor_left = 0.3
		container.anchor_right = 0.7
		container.anchor_top = 1.0
		container.anchor_bottom = 1.0
		container.offset_top = -90.0
		container.offset_bottom = -4.0
		container.z_index = 55
		add_child(container)
	else:
		action_panel.add_child(container)

	var btn_first := Button.new()
	btn_first.text = tr("STR_GB_GO_FIRST")
	btn_first.custom_minimum_size.x = 325
	btn_first.size_flags_horizontal = Control.SIZE_SHRINK_END if not _is_mobile_layout else Control.SIZE_EXPAND_FILL
	btn_first.pressed.connect(_on_first_player_chosen.bind(true))
	container.add_child(btn_first)

	var btn_second := Button.new()
	btn_second.text = tr("STR_GB_GO_SECOND")
	btn_second.custom_minimum_size.x = 325
	btn_second.size_flags_horizontal = Control.SIZE_SHRINK_END if not _is_mobile_layout else Control.SIZE_EXPAND_FILL
	btn_second.pressed.connect(_on_first_player_chosen.bind(false))
	container.add_child(btn_second)


func _on_first_player_chosen(go_first: bool) -> void:
	if not _first_player_choosing:
		return
	_cleanup_first_player_ui()

	var chosen_id: int = _first_player_chooser_id if go_first else (1 - _first_player_chooser_id)

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("first_player_choice_resolved", 4)
		_rpc_first_player_choice_resolved.rpc_id(NetworkManager.host_peer_id, chosen_id)
	else:
		_first_player_result = chosen_id


## Host -> Client: tell the client to wait while the host chooses
@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_waiting() -> void:
	RpcLogger.log_receive("first_player_waiting", 0)
	if NetworkManager.is_host():
		return
	_first_player_choosing = true
	_show_first_player_waiting()


## Host -> Client: ask the client to choose first/second
@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_choice_requested() -> void:
	RpcLogger.log_receive("first_player_choice_requested", 0)
	if NetworkManager.is_host():
		return
	_first_player_choosing = true
	_first_player_chooser_id = local_player_id
	_show_first_player_choice()


## Client -> Host: resolve the first-player choice
@rpc("any_peer", "call_remote", "reliable")
func _rpc_first_player_choice_resolved(chosen_id: int) -> void:
	RpcLogger.log_receive("first_player_choice_resolved", 4)
	if not NetworkManager.is_host():
		return
	_first_player_result = chosen_id


## Host -> Client: tell waiting client to restore action panel after coin flip
@rpc("any_peer", "call_remote", "reliable")
func _rpc_cleanup_first_player() -> void:
	RpcLogger.log_receive("cleanup_first_player", 0)
	if NetworkManager.is_host():
		return
	_first_player_choosing = false
	_cleanup_first_player_ui()


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
			var min_left := maxf(20.0, _safe_left + 4.0)
			hand_stack.offset_left = maxf(min_left, cards_left - stack_w)
			hand_stack.offset_right = hand_stack.offset_left + stack_w
			var bot_pad := maxf(20.0, _safe_bottom + 4.0)
			hand_stack.offset_top = - (stack_h + bot_pad - 4.0)
			hand_stack.offset_bottom = - bot_pad

			# Position board view toggle directly above the hand stack
			if _mobile_view_toggle_btn:
				var view_gap := 16.0
				var view_w := 55.0
				var view_h := 60.0
				_mobile_view_toggle_btn.offset_left = hand_stack.offset_left
				_mobile_view_toggle_btn.offset_right = hand_stack.offset_left + view_w
				_mobile_view_toggle_btn.offset_bottom = hand_stack.offset_top - view_gap
				_mobile_view_toggle_btn.offset_top = _mobile_view_toggle_btn.offset_bottom - view_h

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
		var opp_min_left := maxf(20.0, _safe_left + 4.0)
		opp_stack.offset_left = maxf(opp_min_left, cards_left - stack_w)
		opp_stack.offset_right = opp_stack.offset_left + stack_w
		# Use generous minimum top padding to avoid iOS screen-edge gesture zone
		# and to sit below the phase label
		var top_pad := maxf(40.0, _safe_top + 24.0)
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
			_apply_safe_area_insets()
		call_deferred("_position_hands")


func _apply_mobile_layout() -> void:
	# --- 1. Safe area insets (iOS notch/dynamic island, Android cutouts) ---
	# Must be computed FIRST so all button positioning can use _safe_left/_safe_right/etc.
	_apply_safe_area_insets()

	# --- 2. Expand board to use full width ---
	var left_spacer := $VBoxContainer/BoardArea/LeftSpacer
	left_spacer.visible = false
	var right_spacer := $VBoxContainer/BoardArea/RightSpacer
	right_spacer.visible = false
	var board_column := $VBoxContainer/BoardArea/BoardColumn
	board_column.size_flags_stretch_ratio = 1.0

	# --- 3. Reserve bottom space for action panel, eliminate top spacer ---
	$VBoxContainer/TopSpacer.custom_minimum_size.y = 0
	$VBoxContainer/BottomSpacer.custom_minimum_size.y = 100

	# --- 3b. Constrain divider width to board content ---
	var divider := board_column.get_node("Divider") as ColorRect
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_update_mobile_divider.call_deferred()
	player1_board.resized.connect(_update_mobile_divider.call_deferred)
	player2_board.resized.connect(_update_mobile_divider.call_deferred)

	# --- 4. Board view sizing + toggle button ---
	_apply_mobile_board_view()
	_setup_mobile_view_toggle()

	# --- 5. Log panel as slide-out tray on the left ---
	_setup_mobile_log_tray()

	# --- 5b. CP/Threat tray above log button ---
	_setup_mobile_cp_tray()

	# --- 6. Hide card hover preview (mobile uses tap-to-zoom) ---
	if _preview_container:
		_preview_container.visible = false

	# --- 7. Touch-friendly action panel (full width at bottom) ---
	_apply_mobile_action_panel()

	# --- 8. Compact utility buttons into menu popup ---
	_apply_mobile_utility_buttons()

	# --- 9. Reposition hand button stacks ---
	_apply_mobile_hand_button_stacks()

	# --- 10. Widen overlay panels ---
	_apply_mobile_overlays()

	# --- 11. Phase indicator in top-right + turn tracker tray on right ---
	_create_mobile_phase_label()
	_setup_mobile_tracker_tray()

	# --- 12. Reposition action prompt ---
	_apply_mobile_action_prompt()

	# --- 13. Re-position hands for wider board ---
	_position_hands()

	# --- 14. Retry safe area after a brief delay ---
	# DisplayServer may not report safe area until the display is fully initialized.
	# If we got zeros, retry shortly so floating buttons get repositioned.
	if _safe_left == 0.0 and _safe_right == 0.0 and _safe_top == 0.0:
		get_tree().create_timer(0.2).timeout.connect(_retry_safe_area_insets, CONNECT_ONE_SHOT)


func _apply_mobile_action_panel() -> void:
	# Hide the default VBoxContainer panel — FAB replaces it
	action_panel.visible = false

	var pad_r := maxf(20.0, _safe_right + 4.0)
	var pad_b := maxf(20.0, _safe_bottom + 4.0)

	# --- Backdrop: full-screen dim overlay when FAB is expanded ---
	_fab_backdrop = ColorRect.new()
	_fab_backdrop.color = Color(0, 0, 0, 0.4)
	_fab_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fab_backdrop.z_index = 56
	_fab_backdrop.visible = false
	_fab_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fab_backdrop)
	_fab_backdrop.gui_input.connect(_on_fab_backdrop_input)

	# --- FAB container: holds the 5 action buttons + labels ---
	var btn_size := 85.0
	var col_gap := 12.0
	var row_gap := 8.0
	var label_h := 18.0
	var cell_h := btn_size + label_h + 2.0 # 105
	var grid_cols := 3
	var grid_w := btn_size * grid_cols + col_gap * (grid_cols - 1) # 279
	var container_w := grid_w + 20.0 # 299
	var container_h := cell_h * 2.0 + row_gap + btn_size + 8.0 # 311

	_fab_container = Control.new()
	_fab_container.anchor_left = 1.0
	_fab_container.anchor_right = 1.0
	_fab_container.anchor_top = 1.0
	_fab_container.anchor_bottom = 1.0
	_fab_container.offset_left = - (pad_r + container_w)
	_fab_container.offset_right = - pad_r
	_fab_container.offset_top = - (pad_b + container_h)
	_fab_container.offset_bottom = - pad_b
	_fab_container.z_index = 57
	_fab_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fab_container)

	# --- Main FAB button (always visible, bottom-right of container) ---
	_fab_main_btn = Button.new()
	_fab_main_btn.custom_minimum_size = Vector2(btn_size, btn_size)
	_fab_main_btn.size = Vector2(btn_size, btn_size)
	_fab_main_btn.position = Vector2(container_w - btn_size, container_h - btn_size)
	_fab_main_btn.pivot_offset = Vector2(btn_size / 2.0, btn_size / 2.0)
	_fab_main_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_fab_main_btn.clip_contents = true
	_fab_main_btn.pressed.connect(_toggle_fab)
	_fab_main_btn.draw.connect(_draw_fab_main_icon)
	_apply_circle_style(_fab_main_btn, Color(0.2, 0.45, 0.8))
	_fab_container.add_child(_fab_main_btn)

	# --- btn_end_main: standalone pill button, always visible alongside FAB ---
	btn_end_main.get_parent().remove_child(btn_end_main)
	btn_end_main.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_fab_container.add_child(btn_end_main)
	# --- btn_confirm / btn_cancel: standalone pill buttons, hidden by default ---
	btn_confirm.get_parent().remove_child(btn_confirm)
	btn_confirm.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn_confirm.disabled = true
	_fab_container.add_child(btn_confirm)
	btn_cancel.get_parent().remove_child(btn_cancel)
	btn_cancel.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn_cancel.disabled = true
	_fab_container.add_child(btn_cancel)
	_setup_standalone_buttons()

	# --- Reparent 5 action buttons into the FAB grid ---
	# Row 0: Battle, Monster, Strategy (3 cols)
	# Row 1: Rage, Invade (2 cols, centered)
	var btn_order: Array[Button] = [
		btn_play_battle, btn_play_monster, btn_play_strategy,
		btn_gain_rage, btn_invade
	]
	var btn_labels_text: Array = [
		"Battle", "Monster", "Strategy",
		"Rage", "Invade"
	]
	var btn_textures: Array[Texture2D] = [
		load("res://assets/buttons/battle.png"),
		load("res://assets/buttons/monster.png"),
		load("res://assets/buttons/strategy.png"),
		load("res://assets/buttons/rage.png"),
		load("res://assets/buttons/invasion.png"),
	]

	var grid_left := (container_w - grid_w) / 2.0
	var fab_center := _fab_main_btn.position + Vector2(btn_size / 2.0, btn_size / 2.0)

	_fab_action_btns.clear()
	_fab_labels.clear()

	for i in range(5):
		var btn: Button = btn_order[i]
		var target_x: float
		var target_y: float
		if i < 3:
			# Row 0: 3 buttons evenly spaced
			target_x = grid_left + i * (btn_size + col_gap)
			target_y = 0.0
		else:
			# Row 1: 2 buttons centered under row 0
			var row1_offset := (grid_w - (btn_size * 2 + col_gap)) / 2.0
			target_x = grid_left + row1_offset + (i - 3) * (btn_size + col_gap)
			target_y = cell_h + row_gap

		btn.get_parent().remove_child(btn)
		btn.custom_minimum_size = Vector2(btn_size, btn_size)
		btn.size = Vector2(btn_size, btn_size)
		btn.text = ""
		btn.clip_contents = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pivot_offset = Vector2(btn_size / 2.0, btn_size / 2.0)
		btn.position = fab_center - Vector2(btn_size / 2.0, btn_size / 2.0)
		btn.scale = Vector2.ZERO
		btn.visible = false
		btn.set_meta("fab_target_pos", Vector2(target_x, target_y))
		_apply_circle_style(btn, Color(0.2, 0.3, 0.5, 0.9))
		btn.draw.connect(_draw_btn_texture.bind(btn, btn_textures[i]))
		btn.pressed.connect(_collapse_fab_instant)
		_fab_container.add_child(btn)
		_fab_action_btns.append(btn)

		# Label below button
		var lbl := Label.new()
		lbl.text = btn_labels_text[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.custom_minimum_size = Vector2(btn_size + 8.0, label_h)
		lbl.size = Vector2(btn_size + 8.0, label_h)
		lbl.position = Vector2(target_x - 4.0, target_y + btn_size + 2.0)
		lbl.visible = false
		_fab_container.add_child(lbl)
		_fab_labels.append(lbl)


func _create_circle_stylebox(bg_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = 28
	sb.corner_radius_top_right = 28
	sb.corner_radius_bottom_left = 28
	sb.corner_radius_bottom_right = 28
	return sb


func _apply_circle_style(btn: Button, base_color: Color = Color(0.2, 0.3, 0.5, 0.9)) -> void:
	btn.add_theme_stylebox_override("normal", _create_circle_stylebox(base_color))
	btn.add_theme_stylebox_override("hover", _create_circle_stylebox(base_color.lightened(0.1)))
	btn.add_theme_stylebox_override("pressed", _create_circle_stylebox(base_color.darkened(0.15)))
	btn.add_theme_stylebox_override("disabled", _create_circle_stylebox(Color(0.3, 0.3, 0.3, 0.5)))


func _setup_standalone_buttons() -> void:
	## Position btn_end_main, btn_confirm, btn_cancel as pill-shaped text buttons above the FAB.
	var pill_w := 138.0
	var pill_h := 55.0
	var gap := 10.0
	var fab_cx := _fab_main_btn.position.x + _fab_main_btn.size.x / 2.0
	var fab_top := _fab_main_btn.position.y

	# btn_end_main: directly above FAB main button
	var end_main_y := fab_top - pill_h - gap
	_apply_pill_style(btn_end_main, pill_w, pill_h, fab_cx, end_main_y)

	# btn_confirm: above btn_end_main
	var confirm_y := end_main_y - pill_h - gap
	_apply_pill_style(btn_confirm, pill_w, pill_h, fab_cx, confirm_y)

	# btn_cancel: above btn_confirm
	var cancel_y := confirm_y - pill_h - gap
	_apply_pill_style(btn_cancel, pill_w, pill_h, fab_cx, cancel_y)


func _apply_pill_style(btn: Button, pill_w: float, pill_h: float, cx: float, y: float) -> void:
	btn.custom_minimum_size = Vector2(pill_w, pill_h)
	btn.size = Vector2(pill_w, pill_h)
	btn.position = Vector2(cx - pill_w / 2.0, y)
	btn.scale = Vector2.ONE
	btn.pivot_offset = Vector2.ZERO
	btn.add_theme_font_size_override("font_size", 18)
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = Color(0.2, 0.3, 0.5, 0.9)
	pill_sb.corner_radius_top_left = 15
	pill_sb.corner_radius_top_right = 15
	pill_sb.corner_radius_bottom_left = 15
	pill_sb.corner_radius_bottom_right = 15
	btn.add_theme_stylebox_override("normal", pill_sb)
	var pill_hover := pill_sb.duplicate()
	pill_hover.bg_color = Color(0.25, 0.35, 0.55, 0.9)
	btn.add_theme_stylebox_override("hover", pill_hover)
	var pill_pressed := pill_sb.duplicate()
	pill_pressed.bg_color = Color(0.15, 0.25, 0.45, 0.9)
	btn.add_theme_stylebox_override("pressed", pill_pressed)
	var pill_disabled := pill_sb.duplicate()
	pill_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)
	btn.add_theme_stylebox_override("disabled", pill_disabled)


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


func _apply_split_pill_style(left_btn: Button, right_btn: Button, height: float, radius: float) -> void:
	var bg_color := Color(0.2, 0.3, 0.5, 0.9)
	var hover_color := Color(0.25, 0.35, 0.55, 0.9)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.9)

	for btn: Button in [left_btn, right_btn]:
		var is_left: bool = btn == left_btn
		btn.custom_minimum_size.y = height
		for state_name in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			match state_name:
				"normal": sb.bg_color = bg_color
				"hover": sb.bg_color = hover_color
				"pressed": sb.bg_color = pressed_color
			sb.corner_radius_top_left = int(radius) if is_left else 0
			sb.corner_radius_bottom_left = int(radius) if is_left else 0
			sb.corner_radius_top_right = 0 if is_left else int(radius)
			sb.corner_radius_bottom_right = 0 if is_left else int(radius)
			btn.add_theme_stylebox_override(state_name, sb)


## Apply a tab/handle style to a button on a screen edge.
## edge_side: "left" = flush left edge, rounded right; "right" = flush right edge, rounded left.
func _apply_tab_style(btn: Button, edge_side: String) -> void:
	var bg_color := Color(0.2, 0.3, 0.5, 0.85)
	var hover_color := Color(0.25, 0.35, 0.55, 0.85)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.85)
	var radius := 14
	var flush_on_left: bool = edge_side == "left"

	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state_name:
			"normal": sb.bg_color = bg_color
			"hover": sb.bg_color = hover_color
			"pressed": sb.bg_color = pressed_color
		# Rounded on the side facing inward (where content expands from)
		sb.corner_radius_top_left = 0 if flush_on_left else radius
		sb.corner_radius_bottom_left = 0 if flush_on_left else radius
		sb.corner_radius_top_right = radius if flush_on_left else 0
		sb.corner_radius_bottom_right = radius if flush_on_left else 0
		btn.add_theme_stylebox_override(state_name, sb)
	var sb_disabled := StyleBoxFlat.new()
	sb_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)
	sb_disabled.corner_radius_top_left = 0 if flush_on_left else radius
	sb_disabled.corner_radius_bottom_left = 0 if flush_on_left else radius
	sb_disabled.corner_radius_top_right = radius if flush_on_left else 0
	sb_disabled.corner_radius_bottom_right = radius if flush_on_left else 0
	btn.add_theme_stylebox_override("disabled", sb_disabled)


func _apply_mobile_utility_buttons() -> void:
	# Hide individual utility buttons — replaced by a single menu popup
	btn_bug_report.visible = false
	btn_concede.visible = false
	btn_main_menu.visible = false
	btn_sound_toggle.visible = false
	btn_music_toggle.visible = false

	# Create a styled menu button in the top-right corner
	_mobile_menu_btn = Button.new()
	_mobile_menu_btn.text = "..."
	_mobile_menu_btn.anchor_left = 1.0
	_mobile_menu_btn.anchor_right = 1.0
	_mobile_menu_btn.anchor_top = 0.0
	_mobile_menu_btn.anchor_bottom = 0.0
	var menu_pad_r := maxf(20.0, _safe_right + 4.0)
	var menu_pad_t := maxf(40.0, _safe_top + 24.0)
	_mobile_menu_btn.offset_left = - (menu_pad_r + 58.0)
	_mobile_menu_btn.offset_top = menu_pad_t
	_mobile_menu_btn.offset_right = - menu_pad_r
	_mobile_menu_btn.offset_bottom = menu_pad_t + 55.0
	_mobile_menu_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mobile_menu_btn.custom_minimum_size.y = 55
	_mobile_menu_btn.add_theme_font_size_override("font_size", 20)
	_mobile_menu_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_mobile_menu_btn.z_index = 50
	_apply_mobile_menu_pill_style(_mobile_menu_btn)
	_mobile_menu_btn.pressed.connect(_toggle_mobile_menu)
	add_child(_mobile_menu_btn)

	# Backdrop: dims screen when menu is open
	_mobile_menu_backdrop = ColorRect.new()
	_mobile_menu_backdrop.color = Color(0, 0, 0, 0.4)
	_mobile_menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_menu_backdrop.z_index = 55
	_mobile_menu_backdrop.visible = false
	_mobile_menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_mobile_menu_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_mobile_menu()
	)
	add_child(_mobile_menu_backdrop)

	# Panel with large option buttons
	_mobile_menu_panel = VBoxContainer.new()
	_mobile_menu_panel.anchor_left = 1.0
	_mobile_menu_panel.anchor_right = 1.0
	_mobile_menu_panel.anchor_top = 0.0
	_mobile_menu_panel.anchor_bottom = 0.0
	var panel_w := 200.0
	var btn_h := 55.0
	var gap := 6.0
	var panel_top := menu_pad_t + 55.0 + 8.0
	_mobile_menu_panel.offset_left = - (menu_pad_r + panel_w)
	_mobile_menu_panel.offset_right = - menu_pad_r
	_mobile_menu_panel.offset_top = panel_top
	_mobile_menu_panel.offset_bottom = panel_top + (btn_h + gap) * 3.0
	_mobile_menu_panel.add_theme_constant_override("separation", int(gap))
	_mobile_menu_panel.z_index = 56
	_mobile_menu_panel.visible = false
	_mobile_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mobile_menu_panel)

	for item in [["Report Bug", _on_bug_report_pressed], ["Concede", _on_concede_pressed], ["Main Menu", _on_main_menu_pressed]]:
		var btn := Button.new()
		btn.text = item[0]
		btn.custom_minimum_size.y = btn_h
		btn.add_theme_font_size_override("font_size", 18)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		_apply_mobile_menu_pill_style(btn)
		btn.pressed.connect(func():
			_close_mobile_menu()
			(item[1] as Callable).call()
		)
		_mobile_menu_panel.add_child(btn)

	# Sound toggle in mobile menu
	var sound_btn := Button.new()
	sound_btn.text = tr("STR_GB_SOUND_FMT").replace("{VAL}", tr(_VOLUME_VALUE_KEYS[GameSettings.sound_volume]))
	sound_btn.custom_minimum_size.y = btn_h
	sound_btn.add_theme_font_size_override("font_size", 18)
	sound_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_mobile_menu_pill_style(sound_btn)
	sound_btn.pressed.connect(func():
		_on_sound_toggle_pressed()
	)
	_mobile_menu_panel.add_child(sound_btn)
	_mobile_sound_button = sound_btn

	# Music toggle in mobile menu
	var music_btn := Button.new()
	music_btn.text = tr("STR_GB_MUSIC_FMT").replace("{VAL}", tr(_VOLUME_VALUE_KEYS[GameSettings.music_volume]))
	music_btn.custom_minimum_size.y = btn_h
	music_btn.add_theme_font_size_override("font_size", 18)
	music_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_mobile_menu_pill_style(music_btn)
	music_btn.pressed.connect(func():
		_on_music_toggle_pressed()
	)
	_mobile_menu_panel.add_child(music_btn)
	_mobile_music_button = music_btn

	# Expand panel height for the extra buttons
	_mobile_menu_panel.offset_bottom += (btn_h + gap) * 2

	# Hand toggle/sort buttons — fire on touch-down
	for btn: Button in [hand_toggle_button, sort_hand_button,
			opponent_hand_toggle_button, opponent_sort_hand_button]:
		btn.custom_minimum_size.y = 60
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	# ShowCards button
	show_cards_button.custom_minimum_size.y = 62
	show_cards_button.add_theme_font_size_override("font_size", 22)
	show_cards_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	# End game buttons
	btn_rematch.custom_minimum_size.y = 60
	btn_rematch.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn_end_menu.custom_minimum_size.y = 60
	btn_end_menu.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func _apply_mobile_menu_pill_style(btn: Button) -> void:
	var bg_color := Color(0.2, 0.3, 0.5, 0.9)
	var hover_color := Color(0.25, 0.35, 0.55, 0.9)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.9)
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state_name:
			"normal": sb.bg_color = bg_color
			"hover": sb.bg_color = hover_color
			"pressed": sb.bg_color = pressed_color
		sb.corner_radius_top_left = 15
		sb.corner_radius_top_right = 15
		sb.corner_radius_bottom_left = 15
		sb.corner_radius_bottom_right = 15
		btn.add_theme_stylebox_override(state_name, sb)


func _toggle_mobile_menu() -> void:
	if _mobile_menu_open:
		_close_mobile_menu()
	else:
		_open_mobile_menu()


func _open_mobile_menu() -> void:
	_mobile_menu_open = true
	_mobile_menu_backdrop.visible = true
	_mobile_menu_panel.visible = true


func _close_mobile_menu() -> void:
	_mobile_menu_open = false
	_mobile_menu_backdrop.visible = false
	_mobile_menu_panel.visible = false


func _update_mobile_divider() -> void:
	var divider := $VBoxContainer/BoardArea/BoardColumn/Divider as ColorRect
	# Use the wider of the two boards' LayoutContainer widths
	var lc1 := player1_board.get_node("LayoutContainer") as Control
	var lc2 := player2_board.get_node("LayoutContainer") as Control
	var w := maxf(lc1.size.x, lc2.size.x)
	if w > 0.0:
		divider.custom_minimum_size.x = w


func _apply_mobile_board_view() -> void:
	var local_board: Control = player1_board if local_player_id == 0 else player2_board
	var opponent_board: Control = player2_board if local_player_id == 0 else player1_board
	match _mobile_board_view:
		MobileBoardView.LOCAL_ENLARGED:
			local_board.size_flags_stretch_ratio = 0.62
			opponent_board.size_flags_stretch_ratio = 0.38
			local_board.apply_mobile_label_scale(1.0)
			opponent_board.apply_mobile_label_scale(0.6)
		MobileBoardView.OPPONENT_ENLARGED:
			local_board.size_flags_stretch_ratio = 0.38
			opponent_board.size_flags_stretch_ratio = 0.62
			local_board.apply_mobile_label_scale(0.6)
			opponent_board.apply_mobile_label_scale(1.0)
		MobileBoardView.BALANCED:
			local_board.size_flags_stretch_ratio = 0.5
			opponent_board.size_flags_stretch_ratio = 0.5
			local_board.apply_mobile_label_scale(1.0)
			opponent_board.apply_mobile_label_scale(1.0)


func _setup_mobile_view_toggle() -> void:
	_mobile_view_toggle_btn = Button.new()
	_mobile_view_toggle_btn.custom_minimum_size = Vector2(55, 60)
	# Anchored to bottom-left — positioned dynamically in _position_hands()
	_mobile_view_toggle_btn.anchor_left = 0.0
	_mobile_view_toggle_btn.anchor_right = 0.0
	_mobile_view_toggle_btn.anchor_top = 1.0
	_mobile_view_toggle_btn.anchor_bottom = 1.0
	_mobile_view_toggle_btn.z_index = 61
	_mobile_view_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_mobile_view_toggle_btn.pressed.connect(_cycle_mobile_board_view)
	add_child(_mobile_view_toggle_btn)
	# Apply pill style matching the hand buttons
	var bg_color := Color(0.2, 0.3, 0.5, 0.9)
	var hover_color := Color(0.25, 0.35, 0.55, 0.9)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.9)
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state_name:
			"normal": sb.bg_color = bg_color
			"hover": sb.bg_color = hover_color
			"pressed": sb.bg_color = pressed_color
		sb.corner_radius_top_left = 15
		sb.corner_radius_top_right = 15
		sb.corner_radius_bottom_left = 15
		sb.corner_radius_bottom_right = 15
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_mobile_view_toggle_btn.add_theme_stylebox_override(state_name, sb)
	# Draw the icon via a custom draw callback
	_mobile_view_toggle_btn.draw.connect(_draw_board_view_icon)
	_mobile_view_toggle_btn.queue_redraw()


func _cycle_mobile_board_view() -> void:
	_mobile_board_view = (_mobile_board_view + 1) % 3
	_apply_mobile_board_view()
	_mobile_view_toggle_btn.queue_redraw()


func _draw_board_view_icon() -> void:
	var btn := _mobile_view_toggle_btn
	if not btn:
		return
	var w := btn.size.x
	var h := btn.size.y
	var pad := 12.0
	var gap := 3.0
	var box_w := w - pad * 2.0
	var total_h := h - pad * 2.0
	var top_ratio: float
	var bot_ratio: float
	match _mobile_board_view:
		MobileBoardView.LOCAL_ENLARGED:
			top_ratio = 0.35 # opponent = small
			bot_ratio = 0.65 # you = large
		MobileBoardView.OPPONENT_ENLARGED:
			top_ratio = 0.65 # opponent = large
			bot_ratio = 0.35 # you = small
		_:
			top_ratio = 0.5
			bot_ratio = 0.5
	var top_h := (total_h - gap) * top_ratio
	var bot_h := (total_h - gap) * bot_ratio
	var x := pad
	var color := Color(0.85, 0.85, 0.85)
	# Top box (opponent)
	btn.draw_rect(Rect2(x, pad, box_w, top_h), color, false, 1.5)
	# Bottom box (you)
	btn.draw_rect(Rect2(x, pad + top_h + gap, box_w, bot_h), color, false, 1.5)


func _setup_mobile_log_tray() -> void:
	var log_panel := $LogPanel as PanelContainer
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	log_bg.corner_radius_top_right = 10
	log_bg.corner_radius_bottom_right = 10
	log_panel.add_theme_stylebox_override("panel", log_bg)
	# Position log panel as a left-side tray that slides in/out
	log_panel.anchor_left = 0.0
	log_panel.anchor_right = 0.0
	log_panel.anchor_top = 0.1
	log_panel.anchor_bottom = 0.85
	log_panel.offset_left = 0.0
	log_panel.offset_right = 320.0
	log_panel.offset_top = 0.0
	log_panel.offset_bottom = 0.0
	log_panel.z_index = 90
	# Start hidden off-screen to the left
	log_panel.position.x = -320.0
	log_panel.visible = true

	# Toggle button pinned to the left edge
	_mobile_log_toggle_btn = Button.new()
	_mobile_log_toggle_btn.text = tr("STR_GB_LOG")
	_mobile_log_toggle_btn.custom_minimum_size = Vector2(50, 75)
	_mobile_log_toggle_btn.anchor_left = 0.0
	_mobile_log_toggle_btn.anchor_right = 0.0
	_mobile_log_toggle_btn.anchor_top = 0.5
	_mobile_log_toggle_btn.anchor_bottom = 0.5
	var log_pad_l := maxf(4.0, _safe_left)
	_mobile_log_toggle_btn.offset_left = log_pad_l
	_mobile_log_toggle_btn.offset_top = -38.0
	_mobile_log_toggle_btn.offset_right = log_pad_l + 50.0
	_mobile_log_toggle_btn.offset_bottom = 37.0
	_mobile_log_toggle_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mobile_log_toggle_btn.add_theme_font_size_override("font_size", 15)
	_mobile_log_toggle_btn.z_index = 91
	_mobile_log_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_tab_style(_mobile_log_toggle_btn, "left")
	_mobile_log_toggle_btn.pressed.connect(_toggle_mobile_log_tray)
	add_child(_mobile_log_toggle_btn)

	# Unread chat badge (red circle with count, hidden by default)
	_mobile_log_badge = Label.new()
	_mobile_log_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mobile_log_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_log_badge.custom_minimum_size = Vector2(25, 25)
	_mobile_log_badge.add_theme_font_size_override("font_size", 14)
	_mobile_log_badge.add_theme_color_override("font_color", Color.WHITE)
	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.85, 0.15, 0.15)
	badge_bg.corner_radius_top_left = 12
	badge_bg.corner_radius_top_right = 12
	badge_bg.corner_radius_bottom_left = 12
	badge_bg.corner_radius_bottom_right = 12
	badge_bg.content_margin_left = 5
	badge_bg.content_margin_right = 5
	_mobile_log_badge.add_theme_stylebox_override("normal", badge_bg)
	_mobile_log_badge.anchor_left = 1.0
	_mobile_log_badge.anchor_top = 0.0
	_mobile_log_badge.offset_left = -8.0
	_mobile_log_badge.offset_top = -6.0
	_mobile_log_badge.offset_right = 12.0
	_mobile_log_badge.offset_bottom = 14.0
	_mobile_log_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_log_badge.visible = false
	_mobile_log_toggle_btn.add_child(_mobile_log_badge)


func _notify_mobile_log_chat() -> void:
	if not _is_mobile_layout or _mobile_log_tray_open:
		return
	_mobile_log_unread += 1
	if _mobile_log_badge:
		_mobile_log_badge.text = str(_mobile_log_unread)
		_mobile_log_badge.visible = true


func _clear_mobile_log_badge() -> void:
	_mobile_log_unread = 0
	if _mobile_log_badge:
		_mobile_log_badge.visible = false


func _toggle_mobile_log_tray() -> void:
	var log_panel := $LogPanel as PanelContainer
	_mobile_log_tray_open = not _mobile_log_tray_open

	if _mobile_log_tween and _mobile_log_tween.is_valid():
		_mobile_log_tween.kill()
	_mobile_log_tween = create_tween()
	_mobile_log_tween.set_ease(Tween.EASE_OUT)
	_mobile_log_tween.set_trans(Tween.TRANS_CUBIC)

	var log_pad := maxf(4.0, _safe_left)
	if _mobile_log_tray_open:
		_clear_mobile_log_badge()
		_mobile_log_tween.tween_property(log_panel, "position:x", 0.0, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_left", 320.0 + log_pad, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_right", 370.0 + log_pad, 0.25)
	else:
		_mobile_log_tween.tween_property(log_panel, "position:x", -320.0, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_left", log_pad, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_right", log_pad + 50.0, 0.25)


func _setup_mobile_cp_tray() -> void:
	# Panel container for CP/Threat display
	_mobile_cp_panel = PanelContainer.new()
	var safe_pad := maxf(0.0, _safe_left)
	_mobile_cp_panel_w = 180.0 + safe_pad
	var cp_bg := StyleBoxFlat.new()
	cp_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	cp_bg.corner_radius_top_right = 10
	cp_bg.corner_radius_bottom_right = 10
	cp_bg.content_margin_left = 12 + safe_pad
	cp_bg.content_margin_right = 12
	cp_bg.content_margin_top = 10
	cp_bg.content_margin_bottom = 10
	_mobile_cp_panel.add_theme_stylebox_override("panel", cp_bg)
	_mobile_cp_panel.anchor_left = 0.0
	_mobile_cp_panel.anchor_right = 0.0
	_mobile_cp_panel.anchor_top = 0.5
	_mobile_cp_panel.anchor_bottom = 0.5
	_mobile_cp_panel.offset_left = 0.0
	_mobile_cp_panel.offset_right = _mobile_cp_panel_w
	_mobile_cp_panel.offset_top = -135.0
	_mobile_cp_panel.offset_bottom = -25.0
	_mobile_cp_panel.z_index = 90
	_mobile_cp_panel.position.x = -_mobile_cp_panel_w
	add_child(_mobile_cp_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_mobile_cp_panel.add_child(vbox)

	# Opponent row (top: CP | Threat)
	var opp_row := HBoxContainer.new()
	_mobile_cp_opp_cp_label = Label.new()
	_mobile_cp_opp_cp_label.text = "0"
	_mobile_cp_opp_cp_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_opp_cp_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_mobile_cp_opp_cp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_opp_cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opp_row.add_child(_mobile_cp_opp_cp_label)
	_mobile_cp_opp_threat_label = Label.new()
	_mobile_cp_opp_threat_label.text = "0"
	_mobile_cp_opp_threat_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_opp_threat_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_mobile_cp_opp_threat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_opp_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opp_row.add_child(_mobile_cp_opp_threat_label)
	vbox.add_child(opp_row)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)

	# Local player row (bottom — Threat | CP, mirrored from opponent)
	var local_row := HBoxContainer.new()
	_mobile_cp_local_threat_label = Label.new()
	_mobile_cp_local_threat_label.text = "0"
	_mobile_cp_local_threat_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_local_threat_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_mobile_cp_local_threat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_local_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_row.add_child(_mobile_cp_local_threat_label)
	_mobile_cp_local_cp_label = Label.new()
	_mobile_cp_local_cp_label.text = "0"
	_mobile_cp_local_cp_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_local_cp_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_mobile_cp_local_cp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_local_cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_row.add_child(_mobile_cp_local_cp_label)
	vbox.add_child(local_row)

	# Toggle button above Log button
	_mobile_cp_toggle_btn = Button.new()
	_mobile_cp_toggle_btn.text = tr("STR_GB_CP")
	_mobile_cp_toggle_btn.custom_minimum_size = Vector2(50, 75)
	_mobile_cp_toggle_btn.anchor_left = 0.0
	_mobile_cp_toggle_btn.anchor_right = 0.0
	_mobile_cp_toggle_btn.anchor_top = 0.5
	_mobile_cp_toggle_btn.anchor_bottom = 0.5
	var cp_pad_l := maxf(4.0, _safe_left)
	_mobile_cp_toggle_btn.offset_left = cp_pad_l
	_mobile_cp_toggle_btn.offset_top = -117.0
	_mobile_cp_toggle_btn.offset_right = cp_pad_l + 50.0
	_mobile_cp_toggle_btn.offset_bottom = -42.0
	_mobile_cp_toggle_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mobile_cp_toggle_btn.add_theme_font_size_override("font_size", 15)
	_mobile_cp_toggle_btn.z_index = 91
	_mobile_cp_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_tab_style(_mobile_cp_toggle_btn, "left")
	_mobile_cp_toggle_btn.pressed.connect(_toggle_mobile_cp_tray)
	add_child(_mobile_cp_toggle_btn)


func _toggle_mobile_cp_tray() -> void:
	_mobile_cp_tray_open = not _mobile_cp_tray_open

	if _mobile_cp_tween and _mobile_cp_tween.is_valid():
		_mobile_cp_tween.kill()
	_mobile_cp_tween = create_tween()
	_mobile_cp_tween.set_ease(Tween.EASE_OUT)
	_mobile_cp_tween.set_trans(Tween.TRANS_CUBIC)

	var cp_pad := maxf(4.0, _safe_left)
	if _mobile_cp_tray_open:
		_mobile_cp_tween.tween_property(_mobile_cp_panel, "position:x", 0.0, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_left", _mobile_cp_panel_w + cp_pad, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_right", _mobile_cp_panel_w + 50.0 + cp_pad, 0.25)
	else:
		_mobile_cp_tween.tween_property(_mobile_cp_panel, "position:x", -_mobile_cp_panel_w, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_left", cp_pad, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_right", cp_pad + 50.0, 0.25)


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


func _sync_mobile_cp_tray() -> void:
	if not _mobile_cp_opp_cp_label:
		return
	var states: Array[PlayerState] = [null, null]
	var cp_mods: Array[int] = [0, 0]
	var threat_mods: Array[int] = [0, 0]
	if turn_manager and turn_manager.game_state:
		states[0] = turn_manager.game_state.players[0]
		states[1] = turn_manager.game_state.players[1]
		var eh := turn_manager.effect_handler
		if eh:
			for pid in 2:
				cp_mods[pid] += eh.get_monster_cp_modifier(pid)
				var zone_cp: Array = eh.get_zone_cp_modifiers(pid)
				var strat_cp: Array = eh.get_strategy_cp_modifiers(pid)
				for v in zone_cp: cp_mods[pid] += v
				for v in strat_cp: cp_mods[pid] += v
				threat_mods[pid] = eh.get_threat_level_modifier(pid)
	elif not _client_players.is_empty():
		states[0] = _client_players[0]
		states[1] = _client_players[1]
		cp_mods[0] = _client_cp_modifiers[0]
		cp_mods[1] = _client_cp_modifiers[1]
		threat_mods[0] = _client_threat_modifiers[0]
		threat_mods[1] = _client_threat_modifiers[1]
	var lid: int = local_player_id
	var oid: int = 1 - lid
	if states[lid]:
		_mobile_cp_local_cp_label.text = _fmt_num(states[lid].get_total_counter_power() + cp_mods[lid])
		_mobile_cp_local_threat_label.text = _fmt_num(states[lid].get_threat_level() + threat_mods[lid])
	if states[oid]:
		_mobile_cp_opp_cp_label.text = _fmt_num(states[oid].get_total_counter_power() + cp_mods[oid])
		_mobile_cp_opp_threat_label.text = _fmt_num(states[oid].get_threat_level() + threat_mods[oid])


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


func _apply_mobile_hand_button_stacks() -> void:
	# Stacks are dynamically positioned in _position_hands() on mobile,
	# placed to the left of the hand / opponent board. Set anchors to 0,0
	# for absolute offset positioning.
	var hand_stack := $HandButtonStack as HBoxContainer
	hand_stack.anchor_left = 0.0
	hand_stack.anchor_right = 0.0
	hand_stack.anchor_top = 0.0
	hand_stack.anchor_bottom = 0.0
	hand_stack.grow_horizontal = Control.GROW_DIRECTION_END
	hand_stack.z_index = 56
	hand_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var opp_stack := $OpponentHandButtonStack as HBoxContainer
	opp_stack.anchor_left = 0.0
	opp_stack.anchor_right = 0.0
	opp_stack.anchor_top = 0.0
	opp_stack.anchor_bottom = 0.0
	opp_stack.grow_horizontal = Control.GROW_DIRECTION_END
	opp_stack.z_index = 56
	opp_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Apply split-pill styling: [▲|Sort] / [▼|Sort]
	_apply_split_pill_style(hand_toggle_button, sort_hand_button, 60.0, 15.0)
	_apply_split_pill_style(opponent_hand_toggle_button, opponent_sort_hand_button, 60.0, 15.0)


func _apply_mobile_action_prompt() -> void:
	# Position action prompt in bottom-left, capped at 25% screen width.
	# Grows vertically upward if text wraps.
	var prompt := $ActionPrompt as PanelContainer
	var pad_l := maxf(20.0, _safe_left + 4.0)
	prompt.anchor_left = 0.0
	prompt.anchor_right = 0.25
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_left = pad_l
	prompt.offset_top = -186.0
	prompt.offset_right = 0.0
	prompt.offset_bottom = -160.0
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.z_index = 56


func _apply_mobile_overlays() -> void:
	# Increase scroll deadzone so touch scrolling doesn't accidentally tap cards
	for scroll_path in [
		"DeckSearchOverlay/DeckSearchPanel/VBox/ScrollContainer",
		"DiscardViewOverlay/DiscardViewPanel/VBox/ScrollContainer",
		"MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/ScrollContainer",
		"ZoneStackViewOverlay/ZoneStackViewPanel/VBox/ScrollContainer",
		"CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/PoolPanel/PoolVBox/ScrollContainer",
		"CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/ScrollContainer",
	]:
		var sc: ScrollContainer = get_node_or_null(scroll_path)
		if sc:
			sc.scroll_deadzone = 40

	# Touch-friendly close/skip/confirm buttons
	for btn: Button in [deck_search_skip, discard_view_close, monster_deck_view_close,
			zone_stack_view_close, deck_arrange_confirm, deck_arrange_view_board,
			deck_search_view_board, card_pool_select_skip, card_pool_select_confirm,
			card_pool_select_view_board]:
		btn.custom_minimum_size.y = 55
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	# Touch-friendly CheckButton toggles
	for cb: CheckButton in [deck_search_show_all, deck_search_stacked,
			discard_view_stacked, monster_deck_view_stacked,
			card_pool_select_show_all, card_pool_select_stacked]:
		cb.custom_minimum_size.y = 55
		cb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func _create_mobile_phase_label() -> void:
	_mobile_phase_label = Label.new()
	_mobile_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mobile_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_phase_label.add_theme_font_size_override("font_size", 13)
	_mobile_phase_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	# Top-right corner
	_mobile_phase_label.anchor_left = 0.5
	_mobile_phase_label.anchor_right = 1.0
	_mobile_phase_label.anchor_top = 0.0
	_mobile_phase_label.anchor_bottom = 0.0
	var phase_pad_r := maxf(60.0, _safe_right + 50.0) # Leave room for "..." menu button
	var phase_pad_t := maxf(20.0, _safe_top + 4.0)
	_mobile_phase_label.offset_left = 0.0
	_mobile_phase_label.offset_top = phase_pad_t
	_mobile_phase_label.offset_right = - phase_pad_r
	_mobile_phase_label.offset_bottom = phase_pad_t + 18.0
	_mobile_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_phase_label.z_index = 50
	add_child(_mobile_phase_label)


func _setup_mobile_tracker_tray() -> void:
	# Move the TurnTracker out of the hidden RightSpacer into a right-side tray
	var tracker := $VBoxContainer/BoardArea/RightSpacer/TurnTracker as VBoxContainer
	var turn_label_margin := $VBoxContainer/BoardArea/RightSpacer/TurnLabelMargin

	# Create a panel to hold the tracker
	var panel := PanelContainer.new()
	panel.name = "MobileTrackerPanel"
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_bg.corner_radius_top_left = 10
	panel_bg.corner_radius_bottom_left = 10
	panel.add_theme_stylebox_override("panel", panel_bg)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.85
	panel.offset_left = -140.0
	panel.offset_right = 0.0
	panel.z_index = 90
	# Start off-screen: shift offsets right by 140px
	panel.offset_left = 0.0
	panel.offset_right = 140.0
	add_child(panel)

	# VBox inside the panel to stack turn label + tracker
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Move turn label into the vbox first
	turn_label_margin.get_parent().remove_child(turn_label_margin)
	vbox.add_child(turn_label_margin)

	# Move tracker into the vbox
	tracker.get_parent().remove_child(tracker)
	vbox.add_child(tracker)
	tracker.visible = true

	# Toggle button pinned to the right edge
	_mobile_tracker_toggle_btn = Button.new()
	_mobile_tracker_toggle_btn.text = tr("STR_GB_TURNS")
	_mobile_tracker_toggle_btn.custom_minimum_size = Vector2(50, 75)
	_mobile_tracker_toggle_btn.anchor_left = 1.0
	_mobile_tracker_toggle_btn.anchor_right = 1.0
	_mobile_tracker_toggle_btn.anchor_top = 0.5
	_mobile_tracker_toggle_btn.anchor_bottom = 0.5
	var trk_pad_r := maxf(4.0, _safe_right)
	_mobile_tracker_toggle_btn.offset_left = - (trk_pad_r + 50.0)
	_mobile_tracker_toggle_btn.offset_top = -38.0
	_mobile_tracker_toggle_btn.offset_right = - trk_pad_r
	_mobile_tracker_toggle_btn.offset_bottom = 37.0
	_mobile_tracker_toggle_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mobile_tracker_toggle_btn.add_theme_font_size_override("font_size", 12)
	_mobile_tracker_toggle_btn.z_index = 91
	_mobile_tracker_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_tab_style(_mobile_tracker_toggle_btn, "right")
	_mobile_tracker_toggle_btn.pressed.connect(_toggle_mobile_tracker_tray)
	add_child(_mobile_tracker_toggle_btn)


func _toggle_mobile_tracker_tray() -> void:
	var panel := get_node_or_null("MobileTrackerPanel") as PanelContainer
	if not panel:
		return
	_mobile_tracker_tray_open = not _mobile_tracker_tray_open

	if _mobile_tracker_tween and _mobile_tracker_tween.is_valid():
		_mobile_tracker_tween.kill()
	_mobile_tracker_tween = create_tween()
	_mobile_tracker_tween.set_ease(Tween.EASE_OUT)
	_mobile_tracker_tween.set_trans(Tween.TRANS_CUBIC)

	var trk_pad := maxf(4.0, _safe_right)
	if _mobile_tracker_tray_open:
		# Slide panel on-screen: offsets go to normal position
		_mobile_tracker_tween.tween_property(panel, "offset_left", - (140.0 + trk_pad), 0.25)
		_mobile_tracker_tween.parallel().tween_property(panel, "offset_right", -trk_pad, 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_left", - (190.0 + trk_pad), 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_right", - (140.0 + trk_pad), 0.25)
	else:
		# Slide panel off-screen to the right
		_mobile_tracker_tween.tween_property(panel, "offset_left", 0.0, 0.25)
		_mobile_tracker_tween.parallel().tween_property(panel, "offset_right", 140.0, 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_left", - (trk_pad + 50.0), 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_right", -trk_pad, 0.25)


func _apply_safe_area_insets() -> void:
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()
	if screen_size.x > 0 and screen_size.y > 0:
		var viewport_size := get_viewport().get_visible_rect().size
		var scale_x := viewport_size.x / float(screen_size.x)
		var scale_y := viewport_size.y / float(screen_size.y)
		_safe_left = safe_area.position.x * scale_x
		_safe_top = safe_area.position.y * scale_y
		_safe_right = (screen_size.x - (safe_area.position.x + safe_area.size.x)) * scale_x
		_safe_bottom = (screen_size.y - (safe_area.position.y + safe_area.size.y)) * scale_y
		var vbox := $VBoxContainer
		vbox.offset_left = _safe_left
		vbox.offset_right = - _safe_right
		vbox.offset_top = _safe_top


func _retry_safe_area_insets() -> void:
	_apply_safe_area_insets()
	if _safe_left == 0.0 and _safe_right == 0.0 and _safe_top == 0.0:
		return # Still no safe area data — nothing to update
	# Reposition all floating elements with the now-available safe area insets
	var pad_l := maxf(20.0, _safe_left + 4.0)
	var pad_r := maxf(20.0, _safe_right + 4.0)
	var pad_b := maxf(20.0, _safe_bottom + 4.0)
	# FAB container
	if _fab_container:
		var btn_size := 85.0
		var col_gap := 12.0
		var label_h := 18.0
		var cell_h := btn_size + label_h + 2.0
		var row_gap := 8.0
		var grid_w := btn_size * 3 + col_gap * 2
		var container_w := grid_w + 20.0
		var container_h := cell_h * 2.0 + row_gap + btn_size + 8.0
		_fab_container.offset_left = - (pad_r + container_w)
		_fab_container.offset_right = - pad_r
		_fab_container.offset_top = - (pad_b + container_h)
		_fab_container.offset_bottom = - pad_b
		if _fab_main_btn:
			_fab_main_btn.position = Vector2(container_w - btn_size, container_h - btn_size)
	# Log toggle button
	var log_pad := maxf(4.0, _safe_left)
	if _mobile_log_toggle_btn:
		if not _mobile_log_tray_open:
			_mobile_log_toggle_btn.offset_left = log_pad
			_mobile_log_toggle_btn.offset_right = log_pad + 50.0
		else:
			_mobile_log_toggle_btn.offset_left = 320.0 + log_pad
			_mobile_log_toggle_btn.offset_right = 370.0 + log_pad
	# CP toggle button (above log button)
	if _mobile_cp_toggle_btn:
		if not _mobile_cp_tray_open:
			_mobile_cp_toggle_btn.offset_left = log_pad
			_mobile_cp_toggle_btn.offset_right = log_pad + 50.0
		else:
			_mobile_cp_toggle_btn.offset_left = _mobile_cp_panel_w + log_pad
			_mobile_cp_toggle_btn.offset_right = _mobile_cp_panel_w + 50.0 + log_pad
	# Board view toggle button — positioned dynamically in _position_hands()
	# Tracker toggle button
	var trk_pad := maxf(4.0, _safe_right)
	if _mobile_tracker_toggle_btn:
		if not _mobile_tracker_tray_open:
			_mobile_tracker_toggle_btn.offset_left = - (trk_pad + 50.0)
			_mobile_tracker_toggle_btn.offset_right = - trk_pad
		else:
			_mobile_tracker_toggle_btn.offset_left = - (190.0 + trk_pad)
			_mobile_tracker_toggle_btn.offset_right = - (140.0 + trk_pad)
	# Menu button + panel (top-right)
	if _mobile_menu_btn:
		var menu_pad := maxf(20.0, _safe_right + 4.0)
		var menu_pad_t := maxf(40.0, _safe_top + 24.0)
		_mobile_menu_btn.offset_left = - (menu_pad + 58.0)
		_mobile_menu_btn.offset_right = - menu_pad
		_mobile_menu_btn.offset_top = menu_pad_t
		_mobile_menu_btn.offset_bottom = menu_pad_t + 55.0
	if _mobile_menu_panel:
		var menu_pad2 := maxf(20.0, _safe_right + 4.0)
		var menu_pad_t2 := maxf(40.0, _safe_top + 24.0)
		var panel_top := menu_pad_t2 + 55.0 + 8.0
		_mobile_menu_panel.offset_left = - (menu_pad2 + 200.0)
		_mobile_menu_panel.offset_right = - menu_pad2
		_mobile_menu_panel.offset_top = panel_top
	# Phase label (top-right)
	if _mobile_phase_label:
		var phase_pad := maxf(60.0, _safe_right + 50.0)
		var phase_pad_t := maxf(20.0, _safe_top + 4.0)
		_mobile_phase_label.offset_right = - phase_pad
		_mobile_phase_label.offset_top = phase_pad_t
	# Action prompt — width capped at 25% via anchor_right
	var prompt := get_node_or_null("ActionPrompt") as PanelContainer
	if prompt:
		prompt.offset_left = pad_l
		prompt.offset_right = 0.0
	# Hand button stacks update via _position_hands
	_position_hands()


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
		RpcLogger.log_send("submit_action", 4 + params_json.length())
		_rpc_submit_action.rpc_id(NetworkManager.host_peer_id, int(action), params_json)


func _update_turn_tracker(player_id: int, phase: CardEnums.GamePhase, sub_phase: int = 0) -> void:
	var phase_int := int(phase)
	# Collapse: if last queued entry has same player+phase, just update its sub_phase
	if _tracker_queue.size() > 0:
		var last := _tracker_queue[_tracker_queue.size() - 1]
		if last.player_id == player_id and last.phase == phase_int:
			last.sub_phase = sub_phase
			return
	_tracker_queue.append({"player_id": player_id, "phase": phase_int, "sub_phase": sub_phase})
	if not _tracker_draining:
		_drain_tracker_queue()


func _drain_tracker_queue() -> void:
	_tracker_draining = true
	while _tracker_queue.size() > 0:
		var entry := _tracker_queue[0]
		_tracker_queue.remove_at(0)
		var phase_changed: bool = _tracker_last_phase >= 0 and (entry.phase != _tracker_last_phase or entry.player_id != _tracker_last_player)
		_tracker_last_phase = entry.phase
		_tracker_last_player = entry.player_id
		if phase_changed:
			await get_tree().create_timer(PHASE_TRANSITION_DELAY).timeout
		_apply_turn_tracker(entry.player_id, entry.phase as CardEnums.GamePhase, entry.sub_phase)
	_tracker_draining = false


func _apply_turn_tracker(player_id: int, phase: CardEnums.GamePhase, sub_phase: int = 0) -> void:
	var active_color := Color(1.0, 0.9, 0.3, 1.0) # Gold for active phase/sub
	var inactive_color := Color(0.4, 0.4, 0.5, 1.0) # Dim for inactive phases
	var inactive_sub_color := Color(0.35, 0.35, 0.4, 1.0) # Dimmer for inactive sub-phases
	var active_header_color := Color(1.0, 1.0, 1.0, 1.0) # White for active player
	var inactive_header_color := Color(0.6, 0.6, 0.7, 1.0) # Dim for inactive player
	# Update turn number label
	var gs: GameState = turn_manager.game_state if turn_manager else null
	var turn_num: int = gs.turn_number if gs else _client_turn_number
	_turn_label.text = tr("STR_GB_TURN_FMT").replace("{N}", str(turn_num))
	var phase_idx := int(phase)
	for pid in range(2):
		var first_marker := "* " if pid == _first_player_id else "  "
		_turn_tracker_headers[pid].text = first_marker + GameLog.player_name(pid)
		_turn_tracker_headers[pid].add_theme_color_override(
			"font_color", active_header_color if pid == player_id else inactive_header_color)
		for i in range(4):
			var is_active_phase := pid == player_id and i == phase_idx
			var label: Label = _turn_tracker_phases[pid][i]
			label.add_theme_color_override("font_color", active_color if is_active_phase else inactive_color)
			var show_stop := (not is_multiplayer_game or pid == local_player_id) and not _is_setting_auto("auto_phase_advance", pid)
			var auto_indicator := "● " if show_stop else "  "
			label.text = ("► " if is_active_phase else "  ") + auto_indicator + CardEnums.phase_to_string(i as CardEnums.GamePhase)
			var subs: Array = _turn_tracker_subs[pid][i]
			for si in range(subs.size()):
				var sub_label: Label = subs[si]
				var is_active_sub := is_active_phase and si == sub_phase
				sub_label.add_theme_color_override("font_color", active_color if is_active_sub else inactive_sub_color)

	# Update compact mobile phase indicator
	if _mobile_phase_label:
		var phase_name := CardEnums.phase_to_string(phase)
		var pname := GameLog.player_name(player_id)
		_mobile_phase_label.text = tr("STR_GB_TURN_HEADER_FMT").replace("{N}", str(turn_num)).replace("{PLAYER}", pname).replace("{PHASE}", phase_name)


# --- Signal handlers from TurnManager (host/solo only) ---

func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	_current_sub_phase = 0
	_update_turn_tracker(turn_manager.game_state.current_player_id, phase, _current_sub_phase)
	_sync_boards()
	_broadcast_state()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()
	_broadcast_state()


func _on_sub_phase_changed(sub_index: int) -> void:
	_current_sub_phase = sub_index
	_update_turn_tracker(
		turn_manager.game_state.current_player_id,
		turn_manager.game_state.current_phase,
		sub_index)
	_broadcast_state()


func _on_turn_started(player_id: int) -> void:
	_queue_sound("turn_start")
	_current_sub_phase = 0
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
			_pending_interaction = {"method": "action_context", "args": [actions_json, playable_json]}
			for peer_id in NetworkManager.peer_player_map:
				if NetworkManager.peer_player_map[peer_id] == active_id:
					RpcLogger.log_send("receive_action_context", actions_json.length() + playable_json.length())
					_rpc_receive_action_context.rpc_id(peer_id, actions_json, playable_json)
	else:
		_update_action_buttons(valid_actions)


func _on_game_ended(winner_id: int, reason_key: String) -> void:
	SfxManager.play("game_win" if winner_id == local_player_id else "game_lose")
	_action_pending = false
	_game_ended_by_disconnect = false
	# Defensive: hide reconnect overlay if game ends normally
	if _waiting_for_reconnect:
		_waiting_for_reconnect = false
		if _reconnect_overlay:
			_reconnect_overlay.visible = false
	_rematch_requested = false
	_opponent_rematch_requested = false
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		var reason_text := GameLog.render_reason(reason_key)
		win_label.text = tr("STR_GB_WINS_FMT").replace("{NAME}", turn_manager.game_state.player_names[winner_id]) + "\n" + reason_text
	btn_rematch.visible = true
	btn_rematch.disabled = false
	btn_rematch.text = tr("STR_GB_REMATCH")
	_populate_rematch_deck_select()
	_disable_all_buttons()
	if is_multiplayer_game and NetworkManager.is_host():
		# Flush any buffered logs before game end
		if not _pending_log_tokens.is_empty():
			_broadcast_state()
			_flush_broadcast()
		RpcLogger.log_send("receive_game_ended", 4 + reason_key.length())
		_rpc_receive_game_ended.rpc(winner_id, reason_key)
	# Save replay (host)
	if replay_recorder:
		replay_recorder.finish(winner_id, reason_key, _first_player_id)
		replay_recorder.save()
		# Send replay to client so they get a complete copy
		if is_multiplayer_game and NetworkManager.is_host():
			var replay_json := JSON.stringify(replay_recorder._replay.to_dict())
			var compressed := replay_json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
			print("[Replay] Sending replay to client (%d bytes compressed)" % compressed.size())
			_rpc_receive_replay.rpc(compressed)
	RpcLogger.print_summary()
	_upload_stats(winner_id, reason_key, false)


func _on_confirmation_requested(prompt: String, setting: String) -> void:
	var current_pid: int = turn_manager.game_state.current_player_id
	if is_bot_game and current_pid == bot_player.bot_player_id:
		return
	if is_multiplayer_game and current_pid != local_player_id:
		_flush_broadcast()
		_pending_interaction = {"method": "confirmation", "args": [prompt, setting]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == current_pid:
				RpcLogger.log_send("confirmation_requested", prompt.length() + setting.length())
				_rpc_confirmation_requested.rpc_id(peer_id, prompt, setting)
		return
	# Local player: check their per-player settings
	if _player_settings[current_pid].get(setting, false):
		turn_manager.confirm()
		return
	_show_confirmation(prompt)


func _show_confirmation(prompt: String) -> void:
	_awaiting_confirmation = true
	_disable_all_buttons()
	btn_confirm.text = prompt
	_fit_button_text(btn_confirm)
	btn_confirm.disabled = false
	await btn_confirm.pressed
	_awaiting_confirmation = false
	btn_confirm.disabled = true
	btn_confirm.add_theme_font_size_override("font_size", 18)
	if turn_manager:
		turn_manager.confirm()
	elif is_multiplayer_game:
		RpcLogger.log_send("confirmation_resolved", 0)
		_rpc_confirmation_resolved.rpc_id(NetworkManager.host_peer_id)


func _on_state_changed() -> void:
	_sync_boards()
	if not _discard_selecting:
		_update_hand_visibility(_get_current_pid())
	_broadcast_state()
	if replay_recorder:
		replay_recorder.on_state_changed()


func _on_log_message(message) -> void:
	## Accepts a GameLog token Dictionary or a raw String (pre-formatted
	## system messages like reconnect status). Tokens render in the local
	## locale via GameLog.render; strings append as-is.
	_log_tokens.append(message)
	var rendered := _render_log_entry(message)
	if log_output:
		log_output.append_text(rendered + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)
	if is_multiplayer_game and NetworkManager.is_host():
		_pending_log_tokens.append(message)


func _render_log_entry(entry) -> String:
	if typeof(entry) == TYPE_DICTIONARY:
		return GameLog.render(entry)
	return str(entry)


func _on_chat_submitted(text: String) -> void:
	chat_input.clear()
	chat_input.release_focus()
	get_tree().create_timer(0.0).timeout.connect(chat_input.grab_focus)
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	var filtered := ChatFilter.filter(trimmed)
	var token := {"type": "chat", "sender_id": local_player_id, "text": filtered}
	_log_tokens.append(token)
	if log_output:
		log_output.append_text(GameLog.render(token) + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)
	if is_multiplayer_game:
		RpcLogger.log_send("receive_chat", 4 + filtered.length())
		_rpc_receive_chat.rpc(local_player_id, filtered)
	chat_char_count.text = str(chat_input.max_length)


func _on_chat_text_changed(new_text: String) -> void:
	chat_char_count.text = str(chat_input.max_length - new_text.length())


## Queue a sound event for broadcast to the client.
func _queue_sound(sound_name: String) -> void:
	SfxManager.play(sound_name)
	if is_multiplayer_game and NetworkManager.is_host():
		_pending_sound_events.append(sound_name)


func _on_cards_drawn(_player_id: int, _count: int) -> void:
	_queue_sound("card_draw")


func _on_card_discarded(_player_id: int, _card: Dictionary) -> void:
	_queue_sound("card_discard")


func _on_discard_reshuffled() -> void:
	_queue_sound("deck_shuffle")


func _on_rage_gained(_player_id: int, _new_rage: int) -> void:
	_queue_sound("gain_rage")


func _on_card_evolved(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	_queue_sound("card_evolve")


func _on_card_destroyed(_player_id: int, _zone_index: int) -> void:
	_queue_sound("card_destroy")


func _on_strategy_card_played(_player_id: int, _card: Dictionary, _strategy_index: int) -> void:
	_queue_sound("card_play")


# --- Action handler visual feedback ---

func _on_play_cancelled(player_id: int) -> void:
	# Reset the dragged card's scale/state and rearrange hand without reordering
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
	# Sync boards in case the cost prompt changed hand/discard state
	_sync_boards()


func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	_queue_sound("card_play")
	_sync_boards()
	_broadcast_state()


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	_queue_sound("monster_advance")
	_sync_boards()
	_broadcast_state()


func _on_battle_card_crushed(player_id: int, zone_index: int, card: Dictionary) -> void:
	_queue_sound("card_destroy")
	_on_log_message(GameLog.battle_card_crushed(card.get("id", ""), player_id, zone_index))
	_sync_boards()
	_broadcast_state()


func _on_counter_succeeded(player_id: int, total_cp: int, threat: int) -> void:
	_queue_sound("counter_success")
	_on_log_message(GameLog.counter_succeeded(player_id, total_cp, threat))
	_sync_boards()
	_broadcast_state()


func _on_counter_failed(player_id: int, total_cp: int, threat: int) -> void:
	_queue_sound("counter_fail")
	_on_log_message(GameLog.counter_failed(player_id, total_cp, threat))


func _on_counter_immunity_triggered(player_id: int, total_cp: int, threshold: int) -> void:
	_on_log_message(GameLog.counter_immunity(player_id, total_cp, threshold))


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
	if _mobile_sound_button:
		_mobile_sound_button.text = label


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
	if _mobile_music_button:
		_mobile_music_button.text = label


# --- Bug report ---

func _on_bug_report_pressed() -> void:
	var body := _build_bug_report_body()
	var url := "https://github.com/hunterdurbin/godzilla-sim/issues/new?labels=bug&title=Bug+Report&body=" + body.uri_encode()
	OS.shell_open(url)


func _build_bug_report_body() -> String:
	var lines: PackedStringArray = []

	lines.append("## Description")
	lines.append("<!-- Describe the bug -->")
	lines.append("")
	lines.append("## Steps to Reproduce")
	lines.append("1. ")
	lines.append("")
	lines.append("## Expected Behavior")
	lines.append("<!-- What should have happened -->")
	lines.append("")
	lines.append("## Actual Behavior")
	lines.append("<!-- What actually happened -->")
	lines.append("")
	lines.append("## Screenshots")
	lines.append("<!-- Drag and drop screenshots here -->")
	lines.append("")

	# Game state
	lines.append("## Game State")
	var mode_names := {
		NetworkManager.Mode.SOLO: "Solo",
		NetworkManager.Mode.SOLO_BOT: "Solo v Bot",
		NetworkManager.Mode.HOST: "LAN (Host)",
		NetworkManager.Mode.CLIENT: "LAN (Client)",
		NetworkManager.Mode.ONLINE_HOST: "Online (Host)",
		NetworkManager.Mode.ONLINE_CLIENT: "Online (Client)",
	}
	lines.append("- **Version:** %s" % NetworkManager.GAME_VERSION)
	lines.append("- **Mode:** %s" % mode_names.get(NetworkManager.mode, "Unknown"))
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
		var diff_names := {BotConfig.Difficulty.EASY: "Easy", BotConfig.Difficulty.NORMAL: "Normal", BotConfig.Difficulty.HARD: "Hard"}
		lines.append("- **Bot Difficulty:** %s" % diff_names.get(NetworkManager.bot_difficulty, "Unknown"))
		lines.append("- **Bot Seed:** %d" % NetworkManager.bot_seed)
	var gs: GameState = turn_manager.game_state if turn_manager else null
	var turn_num: int = gs.turn_number if gs else _client_turn_number
	var phase: CardEnums.GamePhase = gs.current_phase if gs else _client_phase
	var cur_pid: int = gs.current_player_id if gs else _client_current_player_id
	lines.append("- **Turn:** Turn %d - %s" % [turn_num, GameLog.player_names[cur_pid]])
	lines.append("- **Phase:** %s" % CardEnums.phase_to_string(phase))
	lines.append("")

	for pid in range(2):
		var ps: PlayerState = _get_player_state(pid)
		lines.append("### %s" % GameLog.player_names[pid])
		var monster_name: String = ps.current_monster.get("name", "None") if not ps.current_monster.is_empty() else "None"
		lines.append("- **Monster:** %s (Zone %d)" % [monster_name, ps.monster_zone])
		lines.append("- **Rage:** %d" % ps.rage)
		lines.append("- **Counter Power:** %d" % ps.get_total_counter_power())
		lines.append("- **Threat Level:** %d" % ps.get_threat_level())
		lines.append("- **Deck:** %d cards" % ps.main_deck.size())
		lines.append("- **Discard:** %d cards" % ps.discard_pile.size())
		lines.append("- **Hand:** %d cards" % ps.hand.size())

		# Battle zones (only occupied)
		var occupied: Array[String] = []
		for zi in range(8):
			if ps.zone_has_cards(zi):
				var top_card: Dictionary = ps.get_zone_top_card(zi)
				var stack_size: int = ps.get_zone_stack(zi).size()
				var entry := "Zone %d: %s" % [zi + 1, top_card.get("name", "?")]
				if stack_size > 1:
					entry += " (+%d under)" % (stack_size - 1)
				occupied.append(entry)
		if occupied.size() > 0:
			lines.append("- **Battle Zones:** %s" % ", ".join(occupied))
		else:
			lines.append("- **Battle Zones:** (empty)")

		# Strategy zones
		var strategies: Array[String] = []
		for si in range(ps.strategy_zones.size()):
			var strat: Dictionary = ps.strategy_zones[si]
			if not strat.is_empty():
				strategies.append("Slot %d: %s" % [si + 1, strat.get("name", "?")])
		if strategies.size() > 0:
			lines.append("- **Strategy Zones:** %s" % ", ".join(strategies))
		else:
			lines.append("- **Strategy Zones:** (empty)")
		lines.append("")

	# Game log (last 50 lines)
	if _log_tokens.size() > 0:
		lines.append("<details>")
		lines.append("<summary>Game Log (last 50 lines)</summary>")
		lines.append("")
		lines.append("```")
		var start_idx := maxi(0, _log_tokens.size() - 50)
		for i in range(start_idx, _log_tokens.size()):
			var entry = _log_tokens[i]
			if typeof(entry) == TYPE_DICTIONARY:
				lines.append(GameLog.render_plain(entry))
			else:
				lines.append(GameLog.to_plain_text(str(entry)))
		lines.append("```")
		lines.append("")
		lines.append("</details>")

	return "\n".join(lines)


# --- Concede / Main Menu ---

func _on_concede_pressed() -> void:
	var loser_id := local_player_id
	var winner_id := 1 - loser_id
	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("concede", 0)
		_rpc_concede.rpc_id(NetworkManager.host_peer_id)
	elif turn_manager:
		turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_concede() -> void:
	RpcLogger.log_receive("concede", 0)
	if not NetworkManager.is_host() or not turn_manager:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var loser_id := 1 if sender_id != 1 else 0
	var winner_id := 1 - loser_id
	turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))


func _on_main_menu_pressed() -> void:
	_waiting_for_reconnect = false
	_reconnect_attempting = false
	if _reconnect_overlay:
		_reconnect_overlay.visible = false
	if is_multiplayer_game:
		var connected := multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		if end_game_panel.visible:
			# Game already over — notify rematch declined
			if connected:
				RpcLogger.log_send("rematch_declined", 0)
				_rpc_rematch_declined.rpc()
		elif connected and turn_manager and not turn_manager.is_game_over:
			# Mid-game exit counts as concession
			if NetworkManager.is_host():
				var loser_id := local_player_id
				var winner_id := 1 - loser_id
				turn_manager._on_game_over(winner_id, GameLog.concede_reason_key(loser_id))
			else:
				RpcLogger.log_send("concede", 0)
				_rpc_concede.rpc_id(NetworkManager.host_peer_id)
		GameSettings.clear_reconnect_session()
		NetworkManager.is_in_game = false
		NetworkManager.disconnect_game()
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _on_rematch_pressed() -> void:
	if _game_ended_by_disconnect:
		return

	# Apply local deck change before rematch
	if _rematch_deck_changed and not _rematch_deck_name.is_empty():
		DecklistManager.select_deck_for_player(local_player_id, _rematch_deck_name)

	_rematch_requested = true

	if not is_multiplayer_game:
		_execute_rematch()
		return

	# Multiplayer: notify opponent, wait for them
	btn_rematch.disabled = true
	btn_rematch.text = tr("STR_GB_WAITING")
	_rematch_deck_select.deck_dropdown.disabled = true

	if _rematch_deck_changed and not _rematch_deck_name.is_empty():
		# Send deck data so opponent/host can apply it
		var data := DecklistManager.load_decklist(_rematch_deck_name)
		var payload := JSON.stringify({
			"deck_name": _rematch_deck_name,
			"monster": data.get("monster", []),
			"main": data.get("main", []),
		})
		RpcLogger.log_send("rematch_with_deck", payload.length())
		_rpc_rematch_with_deck.rpc(payload)
	else:
		RpcLogger.log_send("rematch_requested", 0)
		_rpc_rematch_requested.rpc()

	if _opponent_rematch_requested and NetworkManager.is_host():
		_execute_rematch()
		RpcLogger.log_send("execute_rematch", 0)
		_rpc_execute_rematch.rpc()


func _execute_rematch() -> void:
	# 1. Hide end game panel and reset rematch flags
	end_game_panel.visible = false
	_rematch_requested = false
	_opponent_rematch_requested = false
	_game_ended_by_disconnect = false
	_rematch_deck_select.visible = false
	_rematch_deck_select.deck_dropdown.disabled = false
	_rematch_deck_changed = false
	_rematch_deck_name = ""
	_reconnect_cumulative_seconds = 0.0
	_pending_interaction = {}
	# Re-save session with fresh timestamp for the new game
	if is_multiplayer_game and NetworkManager.mode in [NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT]:
		GameSettings.save_reconnect_session(
			NetworkManager.get_game_code(),
			NetworkManager.is_host(),
			NetworkManager.game_mode,
			NetworkManager.is_public_room,
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
	_confirming_pass = false
	_discard_selecting = false
	_discard_player_id = -1
	_discard_count = 0
	_discard_selected_cards.clear()
	_hand_card_selecting = false
	_hand_card_player_id = -1
	_hand_card_allow_skip = false
	_zone_target_selecting = false
	_zone_target_player_id = -1
	_zone_target_board_pid = -1
	_zone_target_valid_zones.clear()
	_zone_target_allow_skip = false
	_strategy_target_selecting = false
	_strategy_target_player_id = -1
	_strategy_target_board_pid = -1
	_strategy_target_valid_indices.clear()
	_choice_selecting = false
	_choice_player_id = -1
	_first_player_choosing = false
	_first_player_chooser_id = -1
	_first_player_result = -1
	_first_player_id = 0
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_card_id = ""
	_selected_card_data = {}
	_zone_select_valid.clear()
	_drag_card = null
	_drag_valid_zones.clear()
	_drag_action = CardEnums.ActionType.PASS
	_drag_can_rage = false
	_drag_can_invade = false
	_hand_expanded = false
	_opponent_hand_expanded = false
	_current_sub_phase = 0
	_tracker_queue.clear()
	_tracker_draining = false
	_tracker_last_phase = -1
	_tracker_last_player = -1
	_state_version = 0
	_client_state_version = 0
	_broadcast_pending = false
	_last_sent_state = {}
	_last_sent_version = 0
	_client_full_state = {}
	_client_gradients_applied = false
	pending_action = CardEnums.ActionType.PASS
	_player_elapsed_ms = [0, 0]
	_turn_start_time_ms = 0
	_game_start_time_ms = 0
	_stats_uploaded = false

	# 5. Restore action panel and hide overlays
	_cleanup_first_player_ui()
	_cleanup_choice_selection()
	_set_action_buttons_visible(true)
	action_prompt_panel.visible = false
	deck_search_overlay.visible = false
	deck_arrange_overlay.visible = false
	card_pool_select_overlay.visible = false
	show_cards_button.visible = false
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
	_client_monster_cp_mods = [0, 0]

	# 7. Clear game log
	_log_tokens.clear()
	if log_output:
		log_output.clear()

	# 8. Reset turn tracker display
	_tracker_queue.clear()
	_tracker_draining = false
	_apply_turn_tracker(0, CardEnums.GamePhase.START, 0)

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

		turn_manager = TurnManager.new()
		turn_manager.setup(CardData)

		turn_manager.game_state.player_names[local_player_id] = GameSettings.player_name
		GameLog.player_names = GameLog.disambiguate(
			turn_manager.game_state.player_names, local_player_id)
		for i in range(2):
			if i < _turn_tracker_headers.size():
				_turn_tracker_headers[i].text = GameLog.player_name(i)

		# Reconnect turn manager signals
		turn_manager.phase_started.connect(_on_phase_started)
		turn_manager.phase_ended.connect(_on_phase_ended)
		turn_manager.sub_phase_changed.connect(_on_sub_phase_changed)
		turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		turn_manager.turn_started.connect(_on_turn_started)
		turn_manager.game_ended.connect(_on_game_ended)
		turn_manager.log_message.connect(_on_log_message)
		turn_manager.confirmation_requested.connect(_on_confirmation_requested)

		# Reconnect action handler signals
		turn_manager.action_handler.cards_drawn.connect(_on_cards_drawn)
		turn_manager.action_handler.card_discarded.connect(_on_card_discarded)
		turn_manager.action_handler.rage_gained.connect(_on_rage_gained)
		turn_manager.action_handler.strategy_card_played.connect(_on_strategy_card_played)
		turn_manager.action_handler.battle_card_played.connect(_on_battle_card_played)
		turn_manager.action_handler.monster_advanced.connect(_on_monster_advanced)
		turn_manager.action_handler.battle_card_crushed.connect(_on_battle_card_crushed)
		turn_manager.action_handler.counter_succeeded.connect(_on_counter_succeeded)
		turn_manager.action_handler.play_cancelled.connect(_on_play_cancelled)
		turn_manager.action_handler.counter_failed.connect(_on_counter_failed)
		turn_manager.action_handler.counter_immunity_triggered.connect(_on_counter_immunity_triggered)
		turn_manager.action_handler.monster_countered.connect(_on_monster_countered)
		turn_manager.action_handler.monster_rankup_requested.connect(_on_monster_rankup_requested)

		# Reconnect effect handler signals
		turn_manager.action_handler.effect_handler.deck_search_requested.connect(_on_deck_search_requested)
		turn_manager.action_handler.effect_handler.deck_arrange_requested.connect(_on_deck_arrange_requested)
		turn_manager.action_handler.effect_handler.card_select_requested.connect(_on_card_select_requested)
		turn_manager.action_handler.effect_handler.hand_discard_requested.connect(_on_hand_discard_requested)
		turn_manager.action_handler.effect_handler.hand_card_selection_requested.connect(_on_hand_card_selection_requested)
		turn_manager.action_handler.effect_handler.zone_target_requested.connect(_on_zone_target_requested)
		turn_manager.action_handler.effect_handler.strategy_target_requested.connect(_on_strategy_target_requested)
		turn_manager.action_handler.effect_handler.effect_zone_highlighted.connect(_on_effect_zone_highlighted)
		turn_manager.action_handler.effect_handler.effect_zone_unhighlighted.connect(_on_effect_zone_unhighlighted)
		turn_manager.action_handler.effect_handler.effect_card_highlighted.connect(_on_effect_card_highlighted)
		turn_manager.action_handler.effect_handler.effect_card_unhighlighted.connect(_on_effect_card_unhighlighted)
		turn_manager.action_handler.effect_handler.choice_requested.connect(_on_choice_requested)
		turn_manager.action_handler.effect_handler.cards_revealed_requested.connect(_on_cards_revealed_requested)
		turn_manager.action_handler.effect_handler.log_message.connect(_on_log_message)
		turn_manager.action_handler.effect_handler.card_evolved.connect(_on_card_evolved)
		turn_manager.action_handler.effect_handler.card_destroyed.connect(_on_card_destroyed)

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
			player.discard_reshuffled.connect(_on_discard_reshuffled)

		# Set up replay recorder for the new game
		_setup_replay_recorder()

		# Start game (coin flip for multiplayer, immediate for solo)
		call_deferred("_start_game")
	else:
		# Client: just wait for state broadcasts from host
		_disable_all_buttons()


# --- Rematch deck select ---

func _setup_rematch_deck_select() -> void:
	var scene := preload("res://scenes/ui/DeckSelect.tscn")
	_rematch_deck_select = scene.instantiate()
	_rematch_deck_select.persist_key = "rematch_deck"
	# Add as direct child of game board, positioned below Save Game button
	add_child(_rematch_deck_select)
	var y_pos := 130.0
	if _save_game_button:
		y_pos = _save_game_button.position.y + _save_game_button.custom_minimum_size.y + 4
	_rematch_deck_select.position = Vector2(10, y_pos)
	_rematch_deck_select.header_label.visible = false
	_rematch_deck_select.visible = false
	_rematch_deck_select.deck_selected.connect(_on_rematch_deck_selected)


func _populate_rematch_deck_select() -> void:
	_rematch_deck_changed = false
	_rematch_deck_name = ""
	var dropdown: OptionButton = _rematch_deck_select.deck_dropdown
	dropdown.clear()
	dropdown.disabled = false

	var current_deck := DecklistManager.get_player_deck_name(local_player_id)
	var all_decks := DecklistManager.get_all_decklists()
	var valid_decks: Array[String] = []

	var skip_validation := not is_multiplayer_game
	for deck_name in all_decks:
		if skip_validation:
			valid_decks.append(deck_name)
			continue
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			continue
		var errors := GameModeValidator.validate(
			NetworkManager.game_mode,
			data.get("monster", []),
			data.get("main", []),
		)
		if errors.is_empty():
			valid_decks.append(deck_name)

	if valid_decks.size() <= 1:
		# No alternative decks to choose from — hide the dropdown
		_rematch_deck_select.visible = false
		return

	var select_idx := 0
	for i in range(valid_decks.size()):
		dropdown.add_item(valid_decks[i])
		if valid_decks[i] == current_deck:
			select_idx = i

	dropdown.select(select_idx)
	_rematch_deck_select.current_selection = valid_decks[select_idx]
	_rematch_deck_select.visible = true


func _on_rematch_deck_selected(deck_name: String) -> void:
	var current_deck := DecklistManager.get_player_deck_name(local_player_id)
	_rematch_deck_changed = deck_name != current_deck
	_rematch_deck_name = deck_name


# --- Rematch RPCs ---

## Peer -> Peer: signal that this player wants a rematch
@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_requested() -> void:
	RpcLogger.log_receive("rematch_requested", 0)
	_opponent_rematch_requested = true
	_on_log_message(GameLog.opponent_wants_rematch(false))

	if _rematch_requested and NetworkManager.is_host():
		_execute_rematch()
		RpcLogger.log_send("execute_rematch", 0)
		_rpc_execute_rematch.rpc()


## Peer -> Peer: rematch request with a changed deck
@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_with_deck(payload_json: String) -> void:
	RpcLogger.log_receive("rematch_with_deck", payload_json.length())
	var json := JSON.new()
	if json.parse(payload_json) != OK:
		push_warning("[Rematch] Failed to parse deck payload")
		return
	var payload: Dictionary = json.data
	var deck_name: String = payload.get("deck_name", "")
	var monster_entries: Array = payload.get("monster", [])
	var main_entries: Array = payload.get("main", [])

	# Validate the deck for the current game mode
	var errors := GameModeValidator.validate(NetworkManager.game_mode, monster_entries, main_entries)
	if not errors.is_empty():
		push_warning("[Rematch] Opponent's deck is invalid for mode '%s': %s" % [NetworkManager.game_mode, str(errors)])
		return

	# Determine sender's player_id from RPC sender peer
	var sender_peer := multiplayer.get_remote_sender_id()
	var sender_pid: int = -1
	for peer_id in NetworkManager.peer_player_map:
		if peer_id == sender_peer:
			sender_pid = NetworkManager.peer_player_map[peer_id]
			break
	if sender_pid == -1:
		push_warning("[Rematch] Could not determine sender player_id")
		return

	DecklistManager.set_player_deck_from_entries(sender_pid, deck_name, monster_entries, main_entries)
	_opponent_rematch_requested = true
	_on_log_message(GameLog.opponent_wants_rematch(true))

	if _rematch_requested and NetworkManager.is_host():
		_execute_rematch()
		RpcLogger.log_send("execute_rematch", 0)
		_rpc_execute_rematch.rpc()


## Host -> Client: instruct client to execute the rematch reset
@rpc("any_peer", "call_remote", "reliable")
func _rpc_execute_rematch() -> void:
	RpcLogger.log_receive("execute_rematch", 0)
	if NetworkManager.is_host():
		return
	_execute_rematch()


## Peer -> Peer: opponent declined rematch (chose Main Menu)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch_declined() -> void:
	RpcLogger.log_receive("rematch_declined", 0)
	var win_label: Label = end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		win_label.text = win_label.text + "\nOpponent returned to menu."
	btn_rematch.visible = false
	_rematch_deck_select.visible = false


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
		playable = turn_manager.rules_engine.get_discardable_cards_for_invade(turn_manager.game_state.get_current_player(), turn_manager.game_state.get_opponent_of_current())
	else:
		playable.assign(_client_playable.get("invade_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.INVADE
	_enter_card_selection("Select a card to discard for Invasion:", playable)


func _on_end_main_pressed() -> void:
	if _player_settings[_get_current_pid()].get("confirm_main_phase_pass", false):
		_enter_pass_confirmation()
		return
	_clear_card_highlight()
	_cancel_selection()
	_submit_action(CardEnums.ActionType.PASS)


func _on_confirm_pressed() -> void:
	if _awaiting_confirmation:
		return
	if _confirming_pass:
		_confirming_pass = false
		_clear_card_highlight()
		_cancel_selection()
		_submit_action(CardEnums.ActionType.PASS)
		return
	if _hand_card_selecting and _hand_card_allow_skip:
		_skip_hand_card_selection()
		return
	if _zone_target_selecting and _zone_target_allow_skip:
		_skip_zone_target()
		return
	if _discard_selecting and _discard_selected_cards.size() == _discard_count:
		_confirm_hand_discard()
		return


func _on_cancel_pressed() -> void:
	if _confirming_pass:
		_cancel_pass_confirmation()
		return
	if waiting_for_card_select or waiting_for_zone_select:
		_clear_card_highlight()
		_cancel_selection()
		if turn_manager:
			_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
		else:
			_update_action_buttons(_client_playable.get("valid_actions", []))
		return


func _enter_pass_confirmation() -> void:
	_confirming_pass = true
	_disable_all_buttons()
	action_prompt_panel.visible = true
	card_select_prompt.text = tr("STR_GB_END_MAIN_QUESTION")
	btn_confirm.text = tr("STR_GB_CONFIRM")
	btn_confirm.disabled = false
	btn_cancel.text = tr("STR_GB_CANCEL")
	btn_cancel.disabled = false


func _cancel_pass_confirmation() -> void:
	_confirming_pass = false
	action_prompt_panel.visible = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	if turn_manager:
		_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
	else:
		_update_action_buttons(_client_playable.get("valid_actions", []))


# --- Card selection flow ---

func _enter_card_selection(prompt_text: String, valid_indices: Array[int]) -> void:
	waiting_for_card_select = true
	card_select_prompt.text = prompt_text
	action_prompt_panel.visible = true
	_disable_all_buttons()
	btn_cancel.text = tr("STR_GB_CANCEL")
	btn_cancel.disabled = false

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

	_set_card_highlight(card)

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
	card_select_prompt.text = tr("STR_GB_SELECT_ZONE")
	var active_pid := _get_current_pid()
	if not is_multiplayer_game and active_pid != local_player_id:
		_temporarily_collapse_opponent_hand()
	else:
		_temporarily_collapse_hand()

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
	# Reconnect overlay display
	if _waiting_for_reconnect and _reconnect_overlay.visible:
		var elapsed_ms := Time.get_ticks_msec() - _reconnect_current_start_ms
		var total_seconds := _reconnect_cumulative_seconds + elapsed_ms / 1000.0
		if NetworkManager.is_host():
			# Host: show countdown until "Claim Win" becomes available
			var remaining := RECONNECT_CLAIM_WIN_SECONDS - total_seconds
			if remaining > 0:
				_reconnect_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(ceili(remaining)))
			else:
				_reconnect_timer_label.text = ""
				if not _reconnect_claim_btn.visible:
					_reconnect_claim_btn.visible = true
		else:
			# Client: show elapsed time reconnecting
			_reconnect_timer_label.text = tr("STR_GB_RECONNECTING_FMT").replace("{N}", str(int(total_seconds)))
		return # Skip normal drag processing while overlay is showing

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
	if event is InputEventMouseButton and event.pressed and chat_input.has_focus():
		if not chat_input.get_global_rect().has_point(event.global_position):
			chat_input.release_focus()

	var _zoom_fresh := card_zoom_overlay.visible and (Engine.get_process_frames() - _zoom_shown_frame) <= 2

	# Pinch-to-zoom and drag-to-pan on card zoom overlay (touch only)
	if card_zoom_overlay.visible and event is InputEventScreenTouch:
		if event.pressed:
			if _zoom_fresh:
				get_viewport().set_input_as_handled()
			else:
				_pinch_touches[event.index] = event.position
				if _pinch_touches.size() == 1:
					_zoom_drag_start = event.position
					_zoom_dragging = false
				elif _pinch_touches.size() == 2:
					_zoom_dragging = false
					var points: Array = _pinch_touches.values()
					_pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
					_pinch_start_scale = card_zoom_container.scale.x
					_pinch_active = true
					_pinch_used = true
				get_viewport().set_input_as_handled()
		else:
			if not _pinch_touches.has(event.index):
				get_viewport().set_input_as_handled()
			else:
				_pinch_touches.erase(event.index)
				if _pinch_active:
					_pinch_active = _pinch_touches.size() >= 2
				elif _pinch_touches.is_empty():
					if _pinch_used or _zoom_dragging:
						_pinch_used = false
						_zoom_dragging = false
					else:
						_hide_card_zoom()
				get_viewport().set_input_as_handled()
		return

	if card_zoom_overlay.visible and event is InputEventScreenDrag:
		var old_pos: Vector2 = _pinch_touches.get(event.index, event.position)
		_pinch_touches[event.index] = event.position
		if _pinch_active and _pinch_touches.size() >= 2:
			# Two-finger pinch zoom + pan simultaneously
			var points: Array = _pinch_touches.values()
			var old_midpoint := old_pos
			# Compute old midpoint from the other finger's current pos and this finger's old pos
			var keys: Array = _pinch_touches.keys()
			var other_idx: int = keys[0] if keys[1] == event.index else keys[1]
			var other_pos: Vector2 = _pinch_touches[other_idx]
			old_midpoint = (old_pos + other_pos) / 2.0
			var new_midpoint: Vector2 = (_pinch_touches[event.index] + other_pos) / 2.0
			# Pan by midpoint delta
			card_zoom_container.position += new_midpoint - old_midpoint
			# Zoom by distance change
			var dist: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
			if _pinch_start_distance > 0.0:
				var new_scale: float = clampf(_pinch_start_scale * dist / _pinch_start_distance, 1.0, PINCH_MAX_SCALE)
				card_zoom_container.scale = Vector2(new_scale, new_scale)
				card_zoom_container.pivot_offset = card_zoom_container.size / 2.0
		elif _pinch_touches.size() == 1:
			# Single-finger drag to pan (with deadzone)
			if not _zoom_dragging:
				if event.position.distance_to(_zoom_drag_start) > ZOOM_DRAG_DEADZONE:
					_zoom_dragging = true
			if _zoom_dragging:
				card_zoom_container.position += event.position - old_pos
		get_viewport().set_input_as_handled()
		return

	# Magnify gesture (trackpad pinch) — scales card zoom
	if card_zoom_overlay.visible and event is InputEventMagnifyGesture:
		_apply_card_zoom(event.factor)
		get_viewport().set_input_as_handled()
		return

	# Dismiss card zoom on any click (must be first — blocks input from reaching overlays behind)
	# Skip emulated mouse events on touch — ScreenTouch handler above covers dismiss
	if card_zoom_overlay.visible and not _zoom_fresh and event is InputEventMouseButton and event.pressed:
		if TouchHelper.is_touch_device():
			get_viewport().set_input_as_handled()
			return
		_hide_card_zoom()
		get_viewport().set_input_as_handled()
		return

	# Dismiss overlays and skip optional prompts (priority order, topmost first)
	# Uses ui_cancel (ESC on keyboard, B/Circle on controller)
	if event.is_action_pressed("ui_cancel"):
		if card_zoom_overlay.visible:
			_hide_card_zoom()
		elif deck_arrange_overlay.visible:
			pass # Mandatory — must confirm
		elif card_pool_select_overlay.visible:
			_on_card_pool_select_skip()
		elif deck_search_overlay.visible:
			_on_deck_search_skip()
		elif discard_view_overlay.visible:
			_hide_discard_view()
		elif monster_deck_view_overlay.visible:
			if _rankup_selecting:
				pass # Mandatory — must pick a monster
			else:
				_hide_monster_deck_view()
		elif zone_stack_view_overlay.visible:
			_hide_zone_stack_view()
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
	if _arrange_dragging_card:
		if event is InputEventMouseMotion:
			_arrange_dragging_card.global_position = get_global_mouse_position() - _arrange_dragging_card.drag_offset
			_update_arrange_drop_indicator()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_arrange_dragging_card.is_dragging = false
			_arrange_dragging_card.z_index = 0
			_on_arrange_card_drag_ended(_arrange_dragging_card)
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


func _cancel_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_card_id = ""
	_selected_card_data = {}
	_zone_select_valid = []
	action_prompt_panel.visible = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	_restore_expanded_hand()
	_restore_expanded_opponent_hand()

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
		if player1_board and not skip_p1:
			player1_board.sync_to_state(state.players[0], cp_mod_0, threat_mod_0, zone_cp_0, strat_cp_0, zone_rank_0, monster_cp_0)
		if player2_board and not skip_p2:
			player2_board.sync_to_state(state.players[1], cp_mod_1, threat_mod_1, zone_cp_1, strat_cp_1, zone_rank_1, monster_cp_1)
	elif not _client_players.is_empty():
		if player1_board and not skip_p1:
			player1_board.sync_to_state(_client_players[0], _client_cp_modifiers[0], _client_threat_modifiers[0], _client_zone_cp_mods[0], _client_strategy_cp_mods[0], _client_zone_rank_mods[0], _client_monster_cp_mods[0])
		if player2_board and not skip_p2:
			player2_board.sync_to_state(_client_players[1], _client_cp_modifiers[1], _client_threat_modifiers[1], _client_zone_cp_mods[1], _client_strategy_cp_mods[1], _client_zone_rank_mods[1], _client_monster_cp_mods[1])
	if _is_mobile_layout:
		_sync_mobile_cp_tray()
	call_deferred("_position_hands")


func _update_hand_visibility(active_player_id: int) -> void:
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


func _update_action_buttons(valid_actions: Array) -> void:
	_confirming_pass = false
	btn_invade.text = tr("STR_GB_INVADE")
	btn_play_battle.disabled = CardEnums.ActionType.PLAY_BATTLE not in valid_actions
	btn_play_strategy.disabled = CardEnums.ActionType.PLAY_STRATEGY not in valid_actions
	btn_gain_rage.disabled = CardEnums.ActionType.GAIN_RAGE not in valid_actions
	btn_play_monster.disabled = CardEnums.ActionType.PLAY_MONSTER not in valid_actions
	btn_invade.disabled = CardEnums.ActionType.INVADE not in valid_actions
	btn_end_main.disabled = false
	btn_end_main.visible = true
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	action_prompt_panel.visible = false
	# Redraw FAB icons to reflect enabled/disabled state
	if _fab_container:
		for btn: Button in _fab_action_btns:
			btn.queue_redraw()


func _disable_all_buttons() -> void:
	btn_play_battle.disabled = true
	btn_play_strategy.disabled = true
	btn_gain_rage.disabled = true
	btn_play_monster.disabled = true
	btn_invade.disabled = true
	btn_end_main.disabled = true
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	if _fab_container:
		for btn: Button in _fab_action_btns:
			btn.queue_redraw()


func _get_active_player_board() -> Control:
	var active_id: int = _get_current_pid()
	if active_id == 0:
		return player1_board
	else:
		return player2_board


## Translate player.hand indices to managed_cards indices by matching card IDs
func _hand_indices_to_visual(hand_indices: Array[int], board: Control, player_id: int = -1) -> Array[int]:
	var player := _get_player_state(player_id) if player_id >= 0 else _get_current_player()
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
				invade_cards = turn_manager.rules_engine.get_discardable_cards_for_invade(player, turn_manager.game_state.get_opponent_of_current())
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

	var active_pid := _get_current_pid()
	if not is_multiplayer_game and active_pid != local_player_id:
		_temporarily_collapse_opponent_hand()
	else:
		_temporarily_collapse_hand()


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
		_restore_expanded_hand()
		_restore_expanded_opponent_hand()
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
					_restore_expanded_hand()
					_restore_expanded_opponent_hand()
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
					_restore_expanded_hand()
					_restore_expanded_opponent_hand()
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
							_restore_expanded_hand()
							_restore_expanded_opponent_hand()
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
						card.is_locked_in_zone = true
						_drag_card = null
						_drag_valid_zones = []
						_restore_expanded_hand()
						_restore_expanded_opponent_hand()
						var params := {"hand_index": hand_idx}
						if _drag_action != CardEnums.ActionType.PLAY_MONSTER:
							params["zone_index"] = i
						_submit_action(_drag_action, params)
						return

	_drag_card = null
	_drag_valid_zones = []
	_drag_can_rage = false
	_drag_can_invade = false
	_restore_expanded_hand()
	_restore_expanded_opponent_hand()


# --- Deck search UI ---

func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast() # Client needs up-to-date state before search
		var matching_json := JSON.stringify(_cards_to_ids(matching_cards))
		var all_json := JSON.stringify(_cards_to_ids(all_cards))
		_pending_interaction = {"method": "deck_search", "args": [matching_json, all_json, prompt]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("deck_search_requested", matching_json.length() + all_json.length() + prompt.length())
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
	deck_search_show_all.set_pressed_no_signal(matching.is_empty())
	deck_search_stacked.set_pressed_no_signal(_match_stacked_view)
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
		var groups := _group_cards(cards, _deck_search_matching_ids)
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
			card.card_right_clicked.connect(_on_card_long_press_zoom)
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
			card.card_right_clicked.connect(_on_card_long_press_zoom)
			deck_search_grid.add_child(card)


func _on_deck_search_toggled(_value: bool) -> void:
	_match_stacked_view = deck_search_stacked.button_pressed
	_refresh_deck_search_grid()


func _on_deck_search_view_board() -> void:
	deck_search_overlay.visible = false
	_view_board_source_overlay = deck_search_overlay
	show_cards_button.visible = true


# --- FAB (Floating Action Button) ---


func _toggle_fab() -> void:
	if _fab_expanded:
		_collapse_fab()
	else:
		_expand_fab()


func _expand_fab() -> void:
	if _fab_expanded:
		return
	_fab_expanded = true

	_fab_backdrop.visible = true
	_fab_backdrop.modulate.a = 0.0

	if _fab_tween and _fab_tween.is_valid():
		_fab_tween.kill()
	_fab_tween = create_tween()
	_fab_tween.set_parallel(true)

	# Fade in backdrop
	_fab_tween.tween_property(_fab_backdrop, "modulate:a", 1.0, 0.2)

	# Rotate FAB "+" to "×" (45°)
	_fab_tween.tween_property(_fab_main_btn, "rotation", deg_to_rad(45.0), 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	var btn_size := 85.0
	var fab_center := _fab_main_btn.position + Vector2(btn_size / 2.0, btn_size / 2.0)

	var count := _fab_action_btns.size()
	for i in range(count):
		var btn: Button = _fab_action_btns[i]
		var lbl: Label = _fab_labels[i]
		var target_pos: Vector2 = btn.get_meta("fab_target_pos")
		var stagger := (count - 1 - i) * 0.03

		btn.visible = true
		btn.position = fab_center - Vector2(btn_size / 2.0, btn_size / 2.0)
		btn.scale = Vector2.ZERO
		btn.custom_minimum_size = Vector2(btn_size, btn_size)
		btn.size = Vector2(btn_size, btn_size)
		btn.text = ""
		btn.pivot_offset = Vector2(btn_size / 2.0, btn_size / 2.0)
		_apply_circle_style(btn, Color(0.2, 0.3, 0.5, 0.9))

		_fab_tween.tween_property(btn, "position", target_pos, 0.25) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_fab_tween.tween_property(btn, "scale", Vector2.ONE, 0.25) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

		lbl.visible = true
		lbl.modulate.a = 0.0
		_fab_tween.tween_property(lbl, "modulate:a", 1.0, 0.15) \
			.set_delay(stagger + 0.15)

	# Hide standalone pills while FAB is expanded
	btn_end_main.visible = false
	btn_confirm.visible = false
	btn_cancel.visible = false

	_fab_main_btn.queue_redraw()


func _collapse_fab() -> void:
	if not _fab_expanded:
		return
	_fab_expanded = false

	if _fab_tween and _fab_tween.is_valid():
		_fab_tween.kill()
	_fab_tween = create_tween()
	_fab_tween.set_parallel(true)

	_fab_tween.tween_property(_fab_backdrop, "modulate:a", 0.0, 0.15)
	_fab_tween.tween_property(_fab_main_btn, "rotation", 0.0, 0.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

	var btn_size := 85.0
	var fab_center := _fab_main_btn.position + Vector2(btn_size / 2.0, btn_size / 2.0)

	var count := _fab_action_btns.size()
	for i in range(count):
		var btn: Button = _fab_action_btns[i]
		var lbl: Label = _fab_labels[i]
		var stagger := i * 0.02

		lbl.visible = false

		_fab_tween.tween_property(btn, "position",
			fab_center - Vector2(btn_size / 2.0, btn_size / 2.0), 0.2) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_fab_tween.tween_property(btn, "scale", Vector2.ZERO, 0.2) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	_fab_tween.chain().tween_callback(func():
		for btn: Button in _fab_action_btns:
			btn.visible = false
		_fab_backdrop.visible = false
		_setup_standalone_buttons()
		btn_end_main.visible = true
		btn_confirm.visible = true
		btn_cancel.visible = true
	)

	_fab_main_btn.queue_redraw()


func _collapse_fab_instant() -> void:
	if not _fab_expanded and not _fab_action_btns.is_empty() and not _fab_action_btns[0].visible:
		# Already collapsed — just ensure standalone button positions
		if _fab_container:
			_setup_standalone_buttons()
		return
	_fab_expanded = false
	if _fab_tween and _fab_tween.is_valid():
		_fab_tween.kill()
	for i in range(_fab_action_btns.size()):
		_fab_action_btns[i].visible = false
		_fab_action_btns[i].scale = Vector2.ZERO
		if i < _fab_labels.size():
			_fab_labels[i].visible = false
	if _fab_backdrop:
		_fab_backdrop.visible = false
	if _fab_main_btn:
		_fab_main_btn.rotation = 0.0
		_fab_main_btn.queue_redraw()
	_setup_standalone_buttons()
	btn_end_main.visible = true
	btn_confirm.visible = true
	btn_cancel.visible = true


func _on_fab_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_collapse_fab()
		get_viewport().set_input_as_handled()


# --- FAB Icon Drawing ---


func _draw_btn_texture(btn: Button, tex: Texture2D) -> void:
	if not btn or not tex:
		return
	var s := btn.size
	var pad := 12.0
	var available := Vector2(s.x - pad * 2, s.y - pad * 2)
	var tex_size := tex.get_size()
	var tex_scale := minf(available.x / tex_size.x, available.y / tex_size.y)
	var draw_size := tex_size * tex_scale
	var pos := Vector2((s.x - draw_size.x) / 2.0, (s.y - draw_size.y) / 2.0)
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	btn.draw_texture_rect(tex, Rect2(pos, draw_size), false, color)


func _draw_fab_main_icon() -> void:
	var btn := _fab_main_btn
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	var arm := 10.0
	var color := Color.WHITE
	# "+" shape — rotation tween makes it look like "×" when expanded
	btn.draw_line(Vector2(cx - arm, cy), Vector2(cx + arm, cy), color, 3.0)
	btn.draw_line(Vector2(cx, cy - arm), Vector2(cx, cy + arm), color, 3.0)


func _draw_icon_battle(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var pad := 14.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var w := 2.5
	# Crossed swords
	btn.draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad), color, w)
	btn.draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad), color, w)
	# Crossguards
	var t := (s.x - pad * 2) * 0.33
	var c1 := Vector2(pad + t, pad + t)
	btn.draw_line(c1 + Vector2(-4, 4), c1 + Vector2(4, -4), color, w)
	var c2 := Vector2(s.x - pad - t, pad + t)
	btn.draw_line(c2 + Vector2(-4, -4), c2 + Vector2(4, 4), color, w)


func _draw_icon_monster(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	var outer_r := s.x / 2.0 - 14.0
	var inner_r := outer_r * 0.4
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var points: PackedVector2Array = []
	for i in range(10):
		var angle := -PI / 2.0 + i * PI / 5.0
		var r := outer_r if i % 2 == 0 else inner_r
		points.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	points.append(points[0])
	btn.draw_polyline(points, color, 2.0)


func _draw_icon_strategy(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	var rx := s.x / 2.0 - 14.0
	var ry := s.y / 2.0 - 12.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	btn.draw_polyline(PackedVector2Array([
		Vector2(cx, cy - ry),
		Vector2(cx + rx, cy),
		Vector2(cx, cy + ry),
		Vector2(cx - rx, cy),
		Vector2(cx, cy - ry),
	]), color, 2.5)


func _draw_icon_end_main(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var pad := 14.0
	# Checkmark
	btn.draw_line(Vector2(pad, s.y * 0.5), Vector2(s.x * 0.4, s.y - pad), color, 2.5)
	btn.draw_line(Vector2(s.x * 0.4, s.y - pad), Vector2(s.x - pad, pad), color, 2.5)


func _draw_icon_rage(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var pad := 14.0
	# Up arrow
	btn.draw_line(Vector2(cx, s.y - pad), Vector2(cx, pad), color, 2.5)
	btn.draw_line(Vector2(cx, pad), Vector2(cx - 8, pad + 10), color, 2.5)
	btn.draw_line(Vector2(cx, pad), Vector2(cx + 8, pad + 10), color, 2.5)


func _draw_icon_invade(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cy := s.y / 2.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var pad := 14.0
	# Right arrow
	btn.draw_line(Vector2(pad, cy), Vector2(s.x - pad, cy), color, 2.5)
	btn.draw_line(Vector2(s.x - pad, cy), Vector2(s.x - pad - 10, cy - 8), color, 2.5)
	btn.draw_line(Vector2(s.x - pad, cy), Vector2(s.x - pad - 10, cy + 8), color, 2.5)


func _on_hand_toggle_pressed() -> void:
	_hand_expanded = not _hand_expanded
	hand_toggle_button.text = "\u25bc" if _hand_expanded else "\u25b2"

	# Determine which hand is the local player's
	var local_hand: Node2D = player1_hand if local_player_id == 0 else player2_hand
	var local_space: Control = player1_hand_space if local_player_id == 0 else player2_hand_space
	if not local_space or not local_hand:
		return

	var rect := local_space.get_global_rect()
	var expand_offset := 120.0 if _is_mobile_layout else HAND_EXPAND_OFFSET
	var y_offset := -expand_offset if _hand_expanded else 0.0
	var target_y := rect.position.y + rect.size.y / 2.0 + y_offset

	_tween_hand_to(local_hand, target_y)


func _on_opponent_hand_toggle_pressed() -> void:
	_opponent_hand_expanded = not _opponent_hand_expanded
	opponent_hand_toggle_button.text = "\u25b2" if _opponent_hand_expanded else "\u25bc"

	var opponent_id := 1 - local_player_id
	var opp_hand: Node2D = player1_hand if opponent_id == 0 else player2_hand
	var opp_space: Control = player1_hand_space if opponent_id == 0 else player2_hand_space
	if not opp_space or not opp_hand:
		return

	var rect := opp_space.get_global_rect()
	var base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
	var target_y := base_y + (OPPONENT_HAND_EXPAND_OFFSET if _opponent_hand_expanded else 0.0)
	_tween_opponent_hand_to(opp_hand, target_y)


const HAND_SORT_TYPE_ORDERS: Array = [
	[0, 1, 2], # Monster, Battle, Strategy
	[0, 2, 1], # Monster, Strategy, Battle
	[1, 0, 2], # Battle, Monster, Strategy
	[1, 2, 0], # Battle, Strategy, Monster
	[2, 0, 1], # Strategy, Monster, Battle
	[2, 1, 0], # Strategy, Battle, Monster
]


func _on_sort_hand_pressed() -> void:
	_sort_player_hand(local_player_id)


func _on_opponent_sort_hand_pressed() -> void:
	_sort_player_hand(1 - local_player_id)


func _sort_player_hand(player_id: int) -> void:
	var hand_mgr: CardManager = player1_hand if player_id == 0 else player2_hand
	if not hand_mgr or hand_mgr.managed_cards.size() <= 1:
		return

	var order: Array = HAND_SORT_TYPE_ORDERS[clampi(GameSettings.hand_sort_type_order, 0, 5)]
	var type_priority := {}
	for i in range(order.size()):
		type_priority[order[i]] = i

	var rank_asc: bool = GameSettings.hand_sort_rank_ascending

	hand_mgr.managed_cards.sort_custom(func(a: Control, b: Control) -> bool:
		var ad: Dictionary = a.card_data if "card_data" in a else {}
		var bd: Dictionary = b.card_data if "card_data" in b else {}
		var pa: int = type_priority.get(int(ad.get("card_type", 0)), 0)
		var pb: int = type_priority.get(int(bd.get("card_type", 0)), 0)
		if pa != pb:
			return pa < pb
		var ra: int = int(ad.get("rank", 0))
		var rb: int = int(bd.get("rank", 0))
		if ra != rb:
			return (ra < rb) if rank_asc else (ra > rb)
		return ad.get("id", "") < bd.get("id", "")
	)

	hand_mgr.arrange_cards(true)


func _temporarily_collapse_hand() -> void:
	if not _hand_expanded:
		return
	var local_hand: Node2D = player1_hand if local_player_id == 0 else player2_hand
	var local_space: Control = player1_hand_space if local_player_id == 0 else player2_hand_space
	if not local_space or not local_hand:
		return
	var rect := local_space.get_global_rect()
	_tween_hand_to(local_hand, rect.position.y + rect.size.y / 2.0)


func _restore_expanded_hand() -> void:
	if not _hand_expanded:
		return
	var local_hand: Node2D = player1_hand if local_player_id == 0 else player2_hand
	var local_space: Control = player1_hand_space if local_player_id == 0 else player2_hand_space
	if not local_space or not local_hand:
		return
	var rect := local_space.get_global_rect()
	var expand_offset := 120.0 if _is_mobile_layout else HAND_EXPAND_OFFSET
	_tween_hand_to(local_hand, rect.position.y + rect.size.y / 2.0 - expand_offset)


func _temporarily_collapse_opponent_hand() -> void:
	if not _opponent_hand_expanded or is_multiplayer_game:
		return
	var opponent_id := 1 - local_player_id
	var opp_hand: Node2D = player1_hand if opponent_id == 0 else player2_hand
	var opp_space: Control = player1_hand_space if opponent_id == 0 else player2_hand_space
	if not opp_space or not opp_hand:
		return
	var rect := opp_space.get_global_rect()
	var base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
	_tween_opponent_hand_to(opp_hand, base_y)


func _restore_expanded_opponent_hand() -> void:
	if not _opponent_hand_expanded or is_multiplayer_game:
		return
	var opponent_id := 1 - local_player_id
	var opp_hand: Node2D = player1_hand if opponent_id == 0 else player2_hand
	var opp_space: Control = player1_hand_space if opponent_id == 0 else player2_hand_space
	if not opp_space or not opp_hand:
		return
	var rect := opp_space.get_global_rect()
	var base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
	_tween_opponent_hand_to(opp_hand, base_y + OPPONENT_HAND_EXPAND_OFFSET)


func _tween_hand_to(hand: Node2D, target_y: float) -> void:
	if _hand_tween and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand_tween = create_tween()
	_hand_tween.set_ease(Tween.EASE_OUT)
	_hand_tween.set_trans(Tween.TRANS_CUBIC)
	_hand_tween.tween_property(hand, "global_position:y", target_y, 0.2)


func _tween_opponent_hand_to(hand: Node2D, target_y: float) -> void:
	if _opponent_hand_tween and _opponent_hand_tween.is_valid():
		_opponent_hand_tween.kill()
	_opponent_hand_tween = create_tween()
	_opponent_hand_tween.set_ease(Tween.EASE_OUT)
	_opponent_hand_tween.set_trans(Tween.TRANS_CUBIC)
	_opponent_hand_tween.tween_property(hand, "global_position:y", target_y, 0.2)


func _set_card_highlight(card: Control) -> void:
	_clear_card_highlight()
	if card and card.has_method("set_highlight"):
		card.set_highlight(true)
		_highlighted_card = card


func _clear_card_highlight() -> void:
	if _highlighted_card and is_instance_valid(_highlighted_card) and _highlighted_card.has_method("set_highlight"):
		_highlighted_card.set_highlight(false)
	_highlighted_card = null


func _on_show_cards_pressed() -> void:
	show_cards_button.visible = false
	if _view_board_source_overlay:
		_view_board_source_overlay.visible = true
	else:
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
	_deck_search_matching = []
	_deck_search_all = []
	_deck_search_matching_ids.clear()


# --- Deck arrange overlay UI ---

func _on_deck_arrange_requested(player_id: int, cards: Array[Dictionary], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var cards_json := JSON.stringify(_cards_to_ids(cards))
		_pending_interaction = {"method": "deck_arrange", "args": [cards_json, prompt]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("deck_arrange_requested", cards_json.length() + prompt.length())
				_rpc_deck_arrange_requested.rpc_id(peer_id, cards_json, prompt)
		return
	_show_deck_arrange(cards, prompt)


func _show_deck_arrange(cards: Array[Dictionary], prompt: String) -> void:
	_arrange_keep = cards.duplicate()
	_arrange_discard = []
	deck_arrange_prompt.text = prompt
	deck_arrange_overlay.visible = true
	_refresh_deck_arrange()


func _refresh_deck_arrange() -> void:
	# Clear existing cards
	for child in deck_arrange_keep_cards.get_children():
		if child.drag_started.is_connected(_on_arrange_card_drag_started):
			child.drag_started.disconnect(_on_arrange_card_drag_started)
		if child.drag_ended.is_connected(_on_arrange_card_drag_ended):
			child.drag_ended.disconnect(_on_arrange_card_drag_ended)
		child.queue_free()
	for child in deck_arrange_discard_cards.get_children():
		if child.drag_started.is_connected(_on_arrange_card_drag_started):
			child.drag_started.disconnect(_on_arrange_card_drag_started)
		if child.drag_ended.is_connected(_on_arrange_card_drag_ended):
			child.drag_ended.disconnect(_on_arrange_card_drag_ended)
		child.queue_free()

	# Populate keep area
	for i in range(_arrange_keep.size()):
		var card_data := _arrange_keep[i]
		var card: Control = _create_arrange_card(card_data)
		card.drag_started.connect(_on_arrange_card_drag_started.bind(card, "keep", i))
		card.drag_ended.connect(_on_arrange_card_drag_ended.bind(card))
		deck_arrange_keep_cards.add_child(card)
		_add_position_badge(card, i + 1)

	# Populate discard area
	for i in range(_arrange_discard.size()):
		var card_data := _arrange_discard[i]
		var card: Control = _create_arrange_card(card_data)
		card.drag_started.connect(_on_arrange_card_drag_started.bind(card, "discard", i))
		card.drag_ended.connect(_on_arrange_card_drag_ended.bind(card))
		deck_arrange_discard_cards.add_child(card)


func _create_arrange_card(card_data: Dictionary) -> Control:
	var card: Control = card_scene.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.custom_minimum_size = Vector2(100, 140)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.drag_enabled = true
	card.is_selectable = false
	_set_gallery_hover(card)
	card.card_right_clicked.connect(_on_card_long_press_zoom)
	return card


func _on_arrange_card_drag_started(card: Control, source: String, index: int) -> void:
	_arrange_dragging_card = card
	_arrange_drag_source = source
	_arrange_drag_index = index
	# Kill hover tween — it keeps running after reparent and overrides position
	if card.tween and card.tween.is_valid():
		card.tween.kill()
	card.scale = Vector2.ONE
	# Create drop indicator (positioned absolutely over the overlay, not inside the grid)
	_arrange_drop_indicator = ColorRect.new()
	_arrange_drop_indicator.custom_minimum_size = Vector2(3, 140)
	_arrange_drop_indicator.size = Vector2(3, 140)
	_arrange_drop_indicator.color = Color(0.4, 0.7, 1.0, 0.9)
	_arrange_drop_indicator.visible = false
	deck_arrange_overlay.add_child(_arrange_drop_indicator)
	# Capture position before reparenting out of grid
	var gpos := card.global_position
	card.get_parent().remove_child(card)
	deck_arrange_overlay.add_child(card)
	# Zero anchors left over from grid layout and restore position
	card.anchor_left = 0.0
	card.anchor_top = 0.0
	card.anchor_right = 0.0
	card.anchor_bottom = 0.0
	card.size = Vector2(100, 140)
	card.global_position = gpos


func _on_arrange_card_drag_ended(card: Control) -> void:
	var card_center := card.global_position + card.size * card.scale / 2.0
	var keep_rect := deck_arrange_keep_panel.get_global_rect()
	var discard_rect := deck_arrange_discard_panel.get_global_rect()

	if keep_rect.has_point(card_center):
		var card_data: Dictionary
		if _arrange_drag_source == "keep":
			card_data = _arrange_keep[_arrange_drag_index]
			_arrange_keep.remove_at(_arrange_drag_index)
		else:
			card_data = _arrange_discard[_arrange_drag_index]
			_arrange_discard.remove_at(_arrange_drag_index)
		var insert_idx := _get_arrange_insert_index(card_center, "keep")
		insert_idx = clampi(insert_idx, 0, _arrange_keep.size())
		_arrange_keep.insert(insert_idx, card_data)
	elif discard_rect.has_point(card_center):
		var card_data: Dictionary
		if _arrange_drag_source == "keep":
			card_data = _arrange_keep[_arrange_drag_index]
			_arrange_keep.remove_at(_arrange_drag_index)
		else:
			card_data = _arrange_discard[_arrange_drag_index]
			_arrange_discard.remove_at(_arrange_drag_index)
		var insert_idx := _get_arrange_insert_index(card_center, "discard")
		insert_idx = clampi(insert_idx, 0, _arrange_discard.size())
		_arrange_discard.insert(insert_idx, card_data)
	# else: dropped outside both panels — no change

	if _arrange_drop_indicator and is_instance_valid(_arrange_drop_indicator):
		_arrange_drop_indicator.queue_free()
		_arrange_drop_indicator = null
	card.queue_free()
	_arrange_dragging_card = null
	_refresh_deck_arrange()


func _get_arrange_insert_index(drop_pos: Vector2, target: String) -> int:
	var container: GridContainer = deck_arrange_keep_cards if target == "keep" else deck_arrange_discard_cards
	var best_idx := container.get_child_count()
	var best_dist := INF
	for i in range(container.get_child_count()):
		var child: Control = container.get_child(i) as Control
		var child_center := child.global_position + child.size * child.scale / 2.0
		var dist: float = drop_pos.distance_squared_to(child_center)
		if dist < best_dist:
			best_dist = dist
			if drop_pos.x < child_center.x:
				best_idx = i
			else:
				best_idx = i + 1
	return best_idx


func _update_arrange_drop_indicator() -> void:
	if not _arrange_drop_indicator or not is_instance_valid(_arrange_drop_indicator):
		return
	var card_center := _arrange_dragging_card.global_position + _arrange_dragging_card.size * _arrange_dragging_card.scale / 2.0
	var keep_rect := deck_arrange_keep_panel.get_global_rect()
	var discard_rect := deck_arrange_discard_panel.get_global_rect()

	var container: GridContainer = null
	var target_name := ""
	if keep_rect.has_point(card_center):
		container = deck_arrange_keep_cards
		target_name = "keep"
	elif discard_rect.has_point(card_center):
		container = deck_arrange_discard_cards
		target_name = "discard"

	if container == null or container.get_child_count() == 0:
		_arrange_drop_indicator.visible = false
		return

	var insert_idx := _get_arrange_insert_index(card_center, target_name)
	insert_idx = clampi(insert_idx, 0, container.get_child_count())

	# Get the reference card for positioning (the card at or just before the insert point)
	var ref_child: Control
	var line_x: float
	if insert_idx < container.get_child_count():
		ref_child = container.get_child(insert_idx) as Control
		line_x = ref_child.global_position.x - 2.0
	else:
		ref_child = container.get_child(container.get_child_count() - 1) as Control
		line_x = ref_child.global_position.x + ref_child.size.x * ref_child.scale.x + 2.0

	_arrange_drop_indicator.global_position = Vector2(line_x, ref_child.global_position.y)
	_arrange_drop_indicator.size.y = ref_child.size.y * ref_child.scale.y
	_arrange_drop_indicator.visible = true


func _add_position_badge(card: Control, pos: int) -> void:
	var badge := Label.new()
	badge.name = "PositionBadge"
	badge.text = str(pos)
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.position = Vector2(8, 8)
	card.add_child(badge)


func _on_deck_arrange_view_board() -> void:
	deck_arrange_overlay.visible = false
	_view_board_source_overlay = deck_arrange_overlay
	show_cards_button.visible = true


func _on_deck_arrange_confirm() -> void:
	deck_arrange_overlay.visible = false
	show_cards_button.visible = false
	_view_board_source_overlay = null
	var keep := _arrange_keep.duplicate()
	var discard := _arrange_discard.duplicate()
	_arrange_keep.clear()
	_arrange_discard.clear()
	# Clear card instances
	for child in deck_arrange_keep_cards.get_children():
		child.queue_free()
	for child in deck_arrange_discard_cards.get_children():
		child.queue_free()
	_resolve_deck_arrange_local(keep, discard)


# --- Card select overlay UI ---

func _on_card_select_requested(player_id: int, matching_cards: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var matching_json := JSON.stringify(_cards_to_ids(matching_cards))
		var all_json := JSON.stringify(_cards_to_ids(all_cards))
		_pending_interaction = {"method": "card_select", "args": [matching_json, all_json, prompt, min_count, max_count]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("card_select_requested", matching_json.length() + all_json.length() + prompt.length())
				_rpc_card_select_requested.rpc_id(peer_id, matching_json, all_json, prompt, min_count, max_count)
		return
	_show_card_select(matching_cards, all_cards, prompt, min_count, max_count)


func _show_card_select(matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int) -> void:
	_card_select_matching = matching
	_card_select_all = all_cards
	_card_select_matching_ids.clear()
	for card_data in matching:
		_card_select_matching_ids[card_data.get("id", "")] = true
	_card_select_selected = []
	_card_select_min_count = min_count
	_card_select_max_count = max_count

	card_pool_select_prompt.text = prompt
	card_pool_select_show_all.set_pressed_no_signal(matching.is_empty())
	card_pool_select_stacked.set_pressed_no_signal(_match_stacked_view)
	card_pool_select_overlay.visible = true

	_refresh_card_select()


func _refresh_card_select() -> void:
	_refresh_card_select_pool()
	_refresh_card_select_selection()
	_update_card_select_buttons()


func _get_card_select_pool() -> Array[Dictionary]:
	var show_all := card_pool_select_show_all.button_pressed
	var source: Array[Dictionary] = _card_select_all if show_all else _card_select_matching
	# Remove selected cards from pool by unique ID (count-aware)
	var selected_ids: Dictionary = {}
	for card in _card_select_selected:
		var id: String = card.get("id", "")
		selected_ids[id] = selected_ids.get(id, 0) + 1
	var pool: Array[Dictionary] = []
	for card in source:
		var id: String = card.get("id", "")
		if selected_ids.get(id, 0) > 0:
			selected_ids[id] -= 1
		else:
			pool.append(card)
	return pool


func _refresh_card_select_pool() -> void:
	var stacked := card_pool_select_stacked.button_pressed
	var show_all := card_pool_select_show_all.button_pressed
	var pool := _get_card_select_pool()
	var all_selectable: bool = not show_all
	var at_limit: bool = _card_select_selected.size() >= _card_select_max_count

	# Get pool filter from effect handler if available
	var pool_filter := Callable()
	if turn_manager:
		pool_filter = turn_manager.action_handler.effect_handler._card_select_pool_filter

	_clear_grid(card_pool_select_pool_grid, _on_card_select_pool_clicked)

	var card_size := Vector2(120, 168)
	if stacked:
		var groups := _group_cards(pool, _card_select_matching_ids)
		for group in groups:
			var card_data: Dictionary = group["card_data"]
			var count: int = group["count"]
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.custom_minimum_size = card_size
			card.size = card_size
			card.drag_enabled = false
			_set_gallery_hover(card)
			var is_match: bool = all_selectable or group["has_match"]
			var passes_filter: bool = not pool_filter.is_valid() or pool_filter.call(card_data, _card_select_selected)
			var can_select: bool = is_match and not at_limit and passes_filter
			card.is_selectable = can_select
			card.click_on_release = true
			if can_select:
				card.card_clicked.connect(_on_card_select_pool_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			card.card_right_clicked.connect(_on_card_long_press_zoom)
			card_pool_select_pool_grid.add_child(card)
			_add_count_badge(card, count)
	else:
		for card_data in pool:
			var card: Control = card_scene.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.custom_minimum_size = card_size
			card.size = card_size
			card.drag_enabled = false
			_set_gallery_hover(card)
			var is_match: bool = all_selectable or _card_select_matching_ids.has(card_data.get("id", ""))
			var passes_filter: bool = not pool_filter.is_valid() or pool_filter.call(card_data, _card_select_selected)
			var can_select: bool = is_match and not at_limit and passes_filter
			card.is_selectable = can_select
			card.click_on_release = true
			if can_select:
				card.card_clicked.connect(_on_card_select_pool_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			card.card_right_clicked.connect(_on_card_long_press_zoom)
			card_pool_select_pool_grid.add_child(card)


func _refresh_card_select_selection() -> void:
	_clear_grid(card_pool_select_selection_grid, _on_card_select_selection_clicked)

	for card_data in _card_select_selected:
		var card: Control = card_scene.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.custom_minimum_size = Vector2(120, 168)
		card.size = Vector2(120, 168)
		card.drag_enabled = false
		card.is_selectable = true
		card.click_on_release = true
		_set_gallery_hover(card)
		card.card_clicked.connect(_on_card_select_selection_clicked)
		card.card_right_clicked.connect(_on_card_long_press_zoom)
		card_pool_select_selection_grid.add_child(card)

	card_pool_select_selection_label.text = tr("STR_GB_SELECTED_FMT").replace("{N}", str(_card_select_selected.size())).replace("{MAX}", str(_card_select_max_count))


func _update_card_select_buttons() -> void:
	var count := _card_select_selected.size()
	card_pool_select_confirm.disabled = count < _card_select_min_count or count > _card_select_max_count
	card_pool_select_confirm.text = tr("STR_GB_CONFIRM_COUNT_FMT").replace("{N}", str(count)).replace("{MAX}", str(_card_select_max_count))


func _on_card_select_pool_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty() or _card_select_selected.size() >= _card_select_max_count:
		return

	var pool := _get_card_select_pool()
	var target_tid := _get_card_template_id(card_data)
	for pool_card in pool:
		if _get_card_template_id(pool_card) == target_tid and _card_select_matching_ids.has(pool_card.get("id", "")):
			_card_select_selected.append(pool_card)
			break

	_refresh_card_select()


func _on_card_select_selection_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty():
		return

	var card_id: String = card_data.get("id", "")
	for i in range(_card_select_selected.size()):
		if _card_select_selected[i].get("id", "") == card_id:
			_card_select_selected.remove_at(i)
			break

	_refresh_card_select()


func _on_card_select_toggled(_value: bool) -> void:
	_match_stacked_view = card_pool_select_stacked.button_pressed
	_refresh_card_select()


func _on_card_pool_select_view_board() -> void:
	card_pool_select_overlay.visible = false
	_view_board_source_overlay = card_pool_select_overlay
	show_cards_button.visible = true


func _on_card_pool_select_skip() -> void:
	_hide_card_select()
	_resolve_card_select_local([])


func _on_card_pool_select_confirm() -> void:
	var sel_count := _card_select_selected.size()
	if sel_count < _card_select_min_count or sel_count > _card_select_max_count:
		return
	var selected := _card_select_selected.duplicate()
	_hide_card_select()
	_resolve_card_select_local(selected)


func _hide_card_select() -> void:
	card_pool_select_overlay.visible = false
	show_cards_button.visible = false
	_view_board_source_overlay = null
	_clear_grid(card_pool_select_pool_grid, _on_card_select_pool_clicked)
	_clear_grid(card_pool_select_selection_grid, _on_card_select_selection_clicked)
	_card_select_matching = []
	_card_select_all = []
	_card_select_matching_ids.clear()
	_card_select_selected = []


# --- Hand discard selection UI ---

func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		_pending_interaction = {"method": "hand_discard", "args": [discard_count]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("hand_discard_requested", 4)
				_rpc_hand_discard_requested.rpc_id(peer_id, discard_count)
		return
	_play_action_required_if_not_turn_player(player_id)
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
	card_select_prompt.text = tr("STR_GB_SELECT_DISCARD_FMT").replace("{N}", str(discard_count))
	action_prompt_panel.visible = true
	btn_confirm.disabled = true


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
		card_select_prompt.text = tr("STR_GB_SELECT_MORE_DISCARD_FMT").replace("{N}", str(remaining))
		btn_confirm.disabled = true
	else:
		card_select_prompt.text = tr("STR_GB_PRESS_CONFIRM_DISCARD")
		btn_confirm.text = tr("STR_GB_CONFIRM")
		btn_confirm.disabled = false


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
	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	# Restore hand visibility
	_update_hand_visibility(_get_current_pid())

	if is_multiplayer_game and _discard_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		# Client sends choice to host
		var indices_json := JSON.stringify(hand_indices)
		RpcLogger.log_send("hand_discard_resolved", indices_json.length())
		_rpc_hand_discard_resolved.rpc_id(NetworkManager.host_peer_id, indices_json)
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

	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	_update_hand_visibility(_get_current_pid())


# --- Hand card selection UI (single-select for effects) ---

func _on_hand_card_selection_requested(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var indices_json := JSON.stringify(valid_indices)
		_pending_interaction = {"method": "hand_card_selection", "args": [indices_json, prompt, allow_skip]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("hand_card_selection_requested", indices_json.length() + prompt.length() + 1)
				_rpc_hand_card_selection_requested.rpc_id(peer_id, indices_json, prompt, allow_skip)
		return
	_play_action_required_if_not_turn_player(player_id)
	_show_hand_card_selection(player_id, valid_indices, prompt, allow_skip)


func _show_hand_card_selection(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> void:
	_hand_card_selecting = true
	_hand_card_player_id = player_id
	_hand_card_allow_skip = allow_skip

	# Flip target player's hand face-up so they can see their cards
	var board: Control = player1_board if player_id == 0 else player2_board
	board.set_hand_face_down(false)

	# Translate player.hand indices to visual managed_cards indices
	var visual_indices := _hand_indices_to_visual(valid_indices, board, player_id)

	var hand_mgr: CardManager = player1_hand if player_id == 0 else player2_hand
	hand_mgr.enter_selection_mode(visual_indices)
	if not hand_mgr.card_selected.is_connected(_on_hand_card_clicked):
		hand_mgr.card_selected.connect(_on_hand_card_clicked)

	_disable_all_buttons()
	card_select_prompt.text = prompt
	action_prompt_panel.visible = true

	if allow_skip:
		btn_confirm.text = tr("STR_GB_SKIP")
		btn_confirm.disabled = false
	else:
		btn_confirm.disabled = true


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
		RpcLogger.log_send("hand_card_selection_resolved", 4)
		_rpc_hand_card_selection_resolved.rpc_id(NetworkManager.host_peer_id, hand_index)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_card_selection(hand_index)


func _skip_hand_card_selection() -> void:
	var hand_mgr: CardManager = player1_hand if _hand_card_player_id == 0 else player2_hand
	_cleanup_hand_card_selection(hand_mgr)

	if is_multiplayer_game and _hand_card_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("hand_card_selection_resolved", 4)
		_rpc_hand_card_selection_resolved.rpc_id(NetworkManager.host_peer_id, -1)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_card_selection(-1)


func _cleanup_hand_card_selection(hand_mgr: CardManager) -> void:
	_hand_card_selecting = false
	hand_mgr.exit_selection_mode()
	if hand_mgr.card_selected.is_connected(_on_hand_card_clicked):
		hand_mgr.card_selected.disconnect(_on_hand_card_clicked)
	action_prompt_panel.visible = false
	btn_confirm.text = tr("STR_GB_CONFIRM")
	btn_confirm.disabled = true
	_update_hand_visibility(_get_current_pid())


# --- Zone target selection UI ---

func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var zones_json := JSON.stringify(valid_zones)
		_pending_interaction = {"method": "zone_target", "args": [target_player_id, zones_json, prompt, allow_skip]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("zone_target_requested", 4 + zones_json.length() + prompt.length() + 1)
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
	action_prompt_panel.visible = true

	if allow_skip:
		btn_confirm.text = tr("STR_GB_SKIP")
		btn_confirm.disabled = false
	else:
		btn_confirm.disabled = true

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
	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("zone_target_resolved", 4)
		_rpc_zone_target_resolved.rpc_id(NetworkManager.host_peer_id, zone_idx)
	else:
		turn_manager.action_handler.effect_handler.resolve_zone_target(zone_idx)


# --- Strategy target selection UI ---

func _on_strategy_target_requested(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var indices_json := JSON.stringify(valid_indices)
		_pending_interaction = {"method": "strategy_target", "args": [target_player_id, indices_json, prompt]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("strategy_target_requested", 4 + indices_json.length() + prompt.length())
				_rpc_strategy_target_requested.rpc_id(peer_id, target_player_id, indices_json, prompt)
		return
	_show_strategy_target_selection(player_id, target_player_id, valid_indices, prompt)


func _show_strategy_target_selection(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> void:
	_strategy_target_selecting = true
	_strategy_target_player_id = player_id
	_strategy_target_board_pid = target_player_id
	_strategy_target_valid_indices = valid_indices

	_disable_all_buttons()
	card_select_prompt.text = prompt
	action_prompt_panel.visible = true

	# Highlight valid strategy slots on the target player's board
	var board: Control = player1_board if target_player_id == 0 else player2_board
	for i in range(board.strategy_slots.size()):
		var slot: Slot = board.strategy_slots[i]
		if slot and i in valid_indices:
			slot.set_highlighted(true)
			slot.in_selection_mode = true
			if not slot.slot_clicked.is_connected(_on_strategy_target_slot_clicked):
				slot.slot_clicked.connect(_on_strategy_target_slot_clicked.bind(i))


func _on_strategy_target_slot_clicked(_zone_num: int, _pid: int, strategy_idx: int) -> void:
	if not _strategy_target_selecting:
		return
	if strategy_idx not in _strategy_target_valid_indices:
		return
	_finish_strategy_target(strategy_idx)


func _finish_strategy_target(strategy_idx: int) -> void:
	# Clean up UI
	var board: Control = player1_board if _strategy_target_board_pid == 0 else player2_board
	for i in range(board.strategy_slots.size()):
		var slot: Slot = board.strategy_slots[i]
		if slot:
			slot.set_highlighted(false)
			slot.in_selection_mode = false
			if slot.slot_clicked.is_connected(_on_strategy_target_slot_clicked):
				slot.slot_clicked.disconnect(_on_strategy_target_slot_clicked)

	_strategy_target_selecting = false
	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("strategy_target_resolved", 4)
		_rpc_strategy_target_resolved.rpc_id(NetworkManager.host_peer_id, strategy_idx)
	else:
		turn_manager.action_handler.effect_handler.resolve_strategy_target(strategy_idx)


# --- Standby ability order choice UI ---

func _on_choice_requested(player_id: int, options: Array[String], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var options_json := JSON.stringify(options)
		_pending_interaction = {"method": "choice", "args": [options_json, prompt]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("choice_requested", options_json.length() + prompt.length())
				_rpc_choice_requested.rpc_id(peer_id, options_json, prompt)
		return
	_show_choice_selection(player_id, options, prompt)


func _show_choice_selection(player_id: int, options: Array[String], prompt: String) -> void:
	_choice_selecting = true
	_choice_player_id = player_id

	_disable_all_buttons()
	# Hide the normal action button rows so only choice buttons show
	_set_action_buttons_visible(false)
	card_select_prompt.text = prompt
	action_prompt_panel.visible = true

	# Create a container for choice buttons
	_choice_container = VBoxContainer.new()
	_choice_container.name = "ChoiceContainer"
	if _is_mobile_layout:
		# On mobile, wrap in a panel anchored to the right side above the bottom bar
		_choice_panel = PanelContainer.new()
		_choice_panel.anchor_left = 1.0
		_choice_panel.anchor_right = 1.0
		_choice_panel.anchor_top = 1.0
		_choice_panel.anchor_bottom = 1.0
		# Grow upward from the bottom spacer area
		_choice_panel.offset_left = -350.0
		_choice_panel.offset_right = -6.0
		_choice_panel.offset_top = -130.0 - options.size() * 50.0
		_choice_panel.offset_bottom = -130.0
		_choice_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_choice_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_choice_panel.z_index = 56
		_choice_panel.add_child(_choice_container)
		add_child(_choice_panel)
	else:
		action_panel.add_child(_choice_container)

	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size.x = 325
		btn.custom_minimum_size.y = 60 if _is_mobile_layout else 0
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END if not _is_mobile_layout else Control.SIZE_EXPAND_FILL
		if _is_mobile_layout:
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pressed.connect(_on_choice_button_pressed.bind(i))
		_choice_container.add_child(btn)
		_choice_buttons.append(btn)


func _on_choice_button_pressed(index: int) -> void:
	if not _choice_selecting:
		return
	_cleanup_choice_selection()

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("choice_resolved", 4)
		_rpc_choice_resolved.rpc_id(NetworkManager.host_peer_id, index)
	else:
		turn_manager.action_handler.effect_handler.resolve_choice(index)


func _cleanup_choice_selection() -> void:
	_choice_selecting = false
	_choice_buttons.clear()
	if _choice_container:
		# On mobile, the container is inside a wrapper panel — free it immediately
		# so a subsequent choice_requested in the same frame gets a clean state.
		if _choice_panel:
			_choice_panel.remove_child(_choice_container)
			_choice_panel.queue_free()
			_choice_panel = null
		_choice_container.queue_free()
		_choice_container = null
	action_prompt_panel.visible = false
	# Restore normal action button rows
	_set_action_buttons_visible(true)


func _on_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	if is_multiplayer_game and pid != local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				RpcLogger.log_send("effect_zone_highlighted", 8)
				_rpc_effect_zone_highlighted.rpc_id(peer_id, pid, zone_index)
		return
	_apply_zone_highlight(pid, zone_index, true)


func _on_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	if is_multiplayer_game and pid != local_player_id:
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == pid:
				RpcLogger.log_send("effect_zone_unhighlighted", 8)
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
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_card_highlighted", 4 + card_id.length())
				_rpc_effect_card_highlighted.rpc_id(peer_id, pid, card_id)
	_apply_card_highlight(pid, card_id, true)


func _on_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	if is_multiplayer_game:
		for peer_id in NetworkManager.peer_player_map:
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_card_unhighlighted", 4 + card_id.length())
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
	_discard_view_cards.reverse()
	var pname := GameLog.player_name(pid)
	var title := "%s Discard Pile (%d)" % [pname, _discard_view_cards.size()]
	discard_view_title.text = title
	discard_view_stacked.set_pressed_no_signal(_match_stacked_view)
	discard_view_overlay.visible = true
	_refresh_discard_view_grid()


func _refresh_discard_view_grid() -> void:
	var stacked := discard_view_stacked.button_pressed

	for child in discard_view_grid.get_children():
		child.queue_free()

	if _discard_view_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("STR_GB_NO_DISCARD")
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
			card.card_right_clicked.connect(_on_card_long_press_zoom)
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
			card.card_right_clicked.connect(_on_card_long_press_zoom)
			discard_view_grid.add_child(card)


func _on_discard_view_stacked_toggled(_value: bool) -> void:
	_match_stacked_view = discard_view_stacked.button_pressed
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
	monster_deck_view_stacked.set_pressed_no_signal(_match_stacked_view)
	monster_deck_view_overlay.visible = true
	_refresh_monster_deck_view_grid()


func _refresh_monster_deck_view_grid() -> void:
	var stacked := monster_deck_view_stacked.button_pressed

	for child in monster_deck_view_grid.get_children():
		child.queue_free()

	if _monster_deck_view_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("STR_GB_NO_MONSTER_DECK")
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
			card.card_right_clicked.connect(_on_card_long_press_zoom)
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
			card.card_right_clicked.connect(_on_card_long_press_zoom)
			monster_deck_view_grid.add_child(card)


func _on_monster_deck_view_stacked_toggled(_value: bool) -> void:
	_match_stacked_view = monster_deck_view_stacked.button_pressed
	_refresh_monster_deck_view_grid()


func _hide_monster_deck_view() -> void:
	if _rankup_selecting:
		return # Cannot dismiss during mandatory rank-up selection
	monster_deck_view_overlay.visible = false
	for child in monster_deck_view_grid.get_children():
		child.queue_free()
	_monster_deck_view_cards.clear()


# --- Monster rank-up selection UI ---

func _on_monster_rankup_requested(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var monsters_json := JSON.stringify(_cards_to_ids(monsters))
		var indices_json := JSON.stringify(valid_indices)
		_pending_interaction = {"method": "monster_rankup", "args": [monsters_json, indices_json, prompt]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("monster_rankup_requested", monsters_json.length() + indices_json.length() + prompt.length())
				_rpc_monster_rankup_requested.rpc_id(peer_id, monsters_json, indices_json, prompt)
		return
	_play_action_required_if_not_turn_player(player_id)
	_show_monster_rankup_selection(player_id, monsters, valid_indices, prompt)


func _play_action_required_if_not_turn_player(player_id: int) -> void:
	if turn_manager and player_id != turn_manager.game_state.current_player_id:
		SfxManager.play("action_required")


func _show_monster_rankup_selection(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String) -> void:
	_rankup_selecting = true
	_rankup_player_id = player_id
	_rankup_valid_indices = valid_indices

	_disable_all_buttons()

	# Show monster deck overlay with selectable cards
	monster_deck_view_title.text = prompt
	monster_deck_view_close.visible = false
	monster_deck_view_stacked.visible = false

	for child in monster_deck_view_grid.get_children():
		child.queue_free()

	for i in range(monsters.size()):
		var card_data := monsters[i]
		var card: Control = card_scene.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.drag_enabled = false
		_set_gallery_hover(card)

		if i in valid_indices:
			card.is_selectable = true
			card.card_clicked.connect(_on_rankup_card_clicked.bind(i))
		else:
			card.is_selectable = false
			card.modulate = Color(0.5, 0.5, 0.5, 1.0)

		card.card_right_clicked.connect(_on_card_long_press_zoom)
		monster_deck_view_grid.add_child(card)

	monster_deck_view_overlay.visible = true


func _on_rankup_card_clicked(_card: Control, index: int) -> void:
	if not _rankup_selecting:
		return
	_cleanup_rankup_selection()

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("monster_rankup_resolved", 4)
		_rpc_monster_rankup_resolved.rpc_id(NetworkManager.host_peer_id, index)
	else:
		turn_manager.action_handler.resolve_monster_rankup(index)


func _cleanup_rankup_selection() -> void:
	_rankup_selecting = false
	_rankup_valid_indices.clear()

	monster_deck_view_overlay.visible = false
	monster_deck_view_close.visible = true
	monster_deck_view_stacked.visible = true
	for child in monster_deck_view_grid.get_children():
		child.queue_free()

	btn_confirm.disabled = true


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
	zone_stack_view_title.text = tr("STR_GB_ZONE_HEADER_FMT").replace("{N}", str(zone_num)).replace("{C}", str(total))
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
		card.card_right_clicked.connect(_on_card_long_press_zoom)
		zone_stack_view_grid.add_child(card)


func _hide_zone_stack_view() -> void:
	zone_stack_view_overlay.visible = false
	for child in zone_stack_view_grid.get_children():
		child.queue_free()
	_zone_stack_view_cards.clear()
	if _cards_revealed_active:
		_cards_revealed_active = false
		turn_manager.action_handler.effect_handler.resolve_cards_revealed()


func _on_cards_revealed_requested(player_id: int, cards: Array[Dictionary], title: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	_zone_stack_view_cards.clear()
	_zone_stack_view_cards.append_array(cards)
	var total: int = _zone_stack_view_cards.size()
	zone_stack_view_title.text = tr("STR_GB_TITLE_COUNT_FMT").replace("{TITLE}", title).replace("{C}", str(total))
	zone_stack_view_overlay.visible = true
	_cards_revealed_active = true
	_refresh_zone_stack_view_grid()


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
	elif player.zone_has_cards(zone_idx):
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


func _on_card_long_press_zoom(card: Control) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		_show_card_zoom(card.card_data)


func _on_hand_card_right_clicked(card: Control, _hand_player_id: int) -> void:
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
		# Strategy card: portrait 405x567 rotated -90° to appear as landscape 567x405.
		# Use a wrapper sized to the landscape dimensions so CenterContainer centers correctly.
		var portrait_size := Vector2(405, 567)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(portrait_size.y, portrait_size.x) # 567x405
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
		card.custom_minimum_size = Vector2(405, 567)
		card_zoom_container.add_child(card)
	card_zoom_overlay.visible = true
	_zoom_shown_frame = Engine.get_process_frames()


func _on_overlay_background_clicked(event: InputEvent, hide_func: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_func.call()


func _on_card_zoom_overlay_input(event: InputEvent) -> void:
	if TouchHelper.is_touch_device():
		return # Touch dismiss handled by _input ScreenTouch handler
	if (Engine.get_process_frames() - _zoom_shown_frame) <= 2:
		return
	if event is InputEventMouseButton and event.pressed:
		_hide_card_zoom()
		get_viewport().set_input_as_handled()


func _hide_card_zoom() -> void:
	card_zoom_overlay.visible = false
	card_zoom_container.scale = Vector2.ONE
	card_zoom_container.position = Vector2.ZERO
	_pinch_touches.clear()
	_pinch_active = false
	_pinch_used = false
	_zoom_dragging = false
	for child in card_zoom_container.get_children():
		child.queue_free()
	# Reset all slot input state so no timers or pending clicks carry over
	for board in [player1_board, player2_board]:
		for slot in board.zone_slots:
			slot.reset_input_state()


func _apply_card_zoom(factor: float) -> void:
	var new_scale: float = clampf(card_zoom_container.scale.x * factor, 1.0, PINCH_MAX_SCALE)
	card_zoom_container.scale = Vector2(new_scale, new_scale)
	card_zoom_container.pivot_offset = card_zoom_container.size / 2.0


# --- Card hover preview ---

func _show_card_preview(data: Dictionary) -> void:
	if _is_mobile_layout:
		return # Mobile uses tap-to-zoom instead of hover preview
	if data.is_empty():
		return
	_preview_card.set_card_data_dict(data)
	var is_strategy: bool = data.get("card_type", -1) == CardEnums.CardType.STRATEGY
	if is_strategy:
		_show_strategy_preview()
	else:
		_show_normal_preview()


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


func _resolve_deck_search_local(selected: Dictionary) -> void:
	if is_multiplayer_game and not NetworkManager.is_host():
		# Client sends selection back to host
		var _search_json := JSON.stringify(selected)
		RpcLogger.log_send("deck_search_resolved", _search_json.length())
		_rpc_deck_search_resolved.rpc_id(NetworkManager.host_peer_id, _search_json)
	else:
		turn_manager.action_handler.effect_handler.resolve_deck_search(selected)


func _resolve_deck_arrange_local(keep: Array[Dictionary], discard: Array[Dictionary]) -> void:
	if is_multiplayer_game and not NetworkManager.is_host():
		var _keep_json := JSON.stringify(keep)
		var _discard_json := JSON.stringify(discard)
		RpcLogger.log_send("deck_arrange_resolved", _keep_json.length() + _discard_json.length())
		_rpc_deck_arrange_resolved.rpc_id(NetworkManager.host_peer_id, _keep_json, _discard_json)
	else:
		turn_manager.action_handler.effect_handler.resolve_deck_arrange(keep, discard)


func _resolve_card_select_local(selected: Array) -> void:
	if is_multiplayer_game and not NetworkManager.is_host():
		var selected_json := JSON.stringify(_cards_to_ids(selected))
		RpcLogger.log_send("card_select_resolved", selected_json.length())
		_rpc_card_select_resolved.rpc_id(NetworkManager.host_peer_id, selected_json)
	else:
		var typed: Array[Dictionary] = []
		for card in selected:
			typed.append(card)
		turn_manager.action_handler.effect_handler.resolve_card_select(typed)


# --- Multiplayer: State broadcast (host -> client) ---

func _broadcast_state() -> void:
	if not is_multiplayer_game or not NetworkManager.is_host():
		return
	if not turn_manager or not turn_manager.game_state:
		return
	if not _broadcast_pending:
		_broadcast_pending = true
		_do_broadcast.call_deferred()


## Force any pending broadcast to send immediately.
## Call before sending RPCs that depend on the client having up-to-date state.
func _flush_broadcast() -> void:
	if _broadcast_pending:
		_do_broadcast()


func _do_broadcast() -> void:
	_broadcast_pending = false
	if not is_multiplayer_game or not NetworkManager.is_host():
		return
	if not turn_manager or not turn_manager.game_state:
		return

	_state_version += 1
	for peer_id in NetworkManager.peer_player_map:
		if peer_id == 1:
			continue # Don't send to self (server peer ID is 1)
		var viewer_id: int = NetworkManager.peer_player_map[peer_id]
		var state_dict := _serialize_game_state(viewer_id)

		var envelope: Dictionary
		if _last_sent_state.is_empty():
			# First broadcast or after resync: send full state
			envelope = {"v": _state_version, "bv": - 1, "d": state_dict}
		else:
			var delta := _compute_delta(_last_sent_state, state_dict)
			if delta.is_empty() and _pending_log_tokens.is_empty() and _pending_sound_events.is_empty():
				# Nothing changed, no logs, no sounds — skip broadcast entirely
				_state_version -= 1
				continue
			envelope = {"v": _state_version, "bv": _last_sent_version, "d": delta}

		# Piggyback buffered log tokens on the envelope (dicts + legacy strings)
		if not _pending_log_tokens.is_empty():
			envelope["log"] = _pending_log_tokens.duplicate()

		# Piggyback buffered sound events on the envelope
		if not _pending_sound_events.is_empty():
			envelope["sfx"] = Array(_pending_sound_events)

		_last_sent_state = state_dict.duplicate(true)
		_last_sent_version = _state_version

		var state_bytes := var_to_bytes(envelope)
		if state_bytes.size() > 32768:
			push_warning("[BROADCAST] Large state packet: %d bytes (v=%d, full=%s)" % [
				state_bytes.size(), _state_version, str(_last_sent_state.is_empty())])
		RpcLogger.log_send("receive_state", state_bytes.size())
		_rpc_receive_state.rpc_id(peer_id, state_bytes)
	_pending_log_tokens.clear()
	_pending_sound_events.clear()


func _serialize_game_state(viewer_id: int) -> Dictionary:
	var gs := turn_manager.game_state
	var eh := turn_manager.effect_handler
	var zone_cp_0: Array = eh.get_zone_cp_modifiers(0) if eh else []
	var zone_cp_1: Array = eh.get_zone_cp_modifiers(1) if eh else []
	var strat_cp_0: Array = eh.get_strategy_cp_modifiers(0) if eh else []
	var strat_cp_1: Array = eh.get_strategy_cp_modifiers(1) if eh else []
	var cp_total_0: int = eh.get_monster_cp_modifier(0) if eh else 0
	var cp_total_1: int = eh.get_monster_cp_modifier(1) if eh else 0
	for v in zone_cp_0: cp_total_0 += v
	for v in zone_cp_1: cp_total_1 += v
	for v in strat_cp_0: cp_total_0 += v
	for v in strat_cp_1: cp_total_1 += v
	var data := {
		"state_version": _state_version,
		"current_player_id": gs.current_player_id,
		"current_phase": int(gs.current_phase),
		"current_sub_phase": _current_sub_phase,
		"turn_number": gs.turn_number,
		"is_game_over": turn_manager.is_game_over,
		"players": [],
		"cp_modifiers": [cp_total_0, cp_total_1],
		"threat_modifiers": [eh.get_threat_level_modifier(0) if eh else 0, eh.get_threat_level_modifier(1) if eh else 0],
		"zone_cp_modifiers": [zone_cp_0, zone_cp_1],
		"strategy_cp_modifiers": [strat_cp_0, strat_cp_1],
		"zone_rank_modifiers": [eh.get_zone_rank_modifiers(0) if eh else [], eh.get_zone_rank_modifiers(1) if eh else []],
		"monster_cp_modifiers": [eh.get_monster_cp_modifier(0) if eh else 0, eh.get_monster_cp_modifier(1) if eh else 0],
		"player_names": Array(gs.player_names),
		"first_player_id": _first_player_id,
	}
	for i in range(2):
		var pd := _serialize_player_state(gs.players[i])
		if i != viewer_id:
			# Strip hand and monster deck data for opponent — only send counts
			# (full hand kept in stats_opponent_hand for disconnect reporting)
			pd["stats_hand"] = pd["hand"].duplicate(true)
			pd.erase("hand")
			pd["monster_deck_count"] = pd["monster_deck"].size()
			pd.erase("monster_deck")
		data["players"].append(pd)
	# Stats data for client disconnect reporting
	data["stats_elapsed_ms"] = Array(_player_elapsed_ms)
	data["stats_game_start_ms"] = _game_start_time_ms
	data["stats_turn_start_ms"] = _turn_start_time_ms
	for i in range(2):
		var deck_name := DecklistManager.get_player_deck_name(i)
		data["players"][i]["stats_deck_name"] = deck_name
		var deck_data = DecklistManager._player_decks[i]
		if deck_data != null:
			data["players"][i]["stats_decklist"] = {
				"main_entries": deck_data["main_entries"],
				"monster_deck": deck_data["monster_deck"],
			}
	# Include hash of shared game state for desync detection
	data["state_hash"] = _compute_state_hash(gs)
	return data


func _card_to_id(card: Dictionary) -> String:
	return card.get("id", "")


func _cards_to_ids(cards: Array) -> Array:
	var ids: Array = []
	for c in cards:
		ids.append(c.get("id", "") if c is Dictionary else "")
	return ids


func _id_to_card(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var base_id := instance_id
	var underscore_pos := instance_id.find("_")
	if underscore_pos != -1:
		base_id = instance_id.substr(0, underscore_pos)
	var template := CardData.get_card_by_id(base_id)
	if template.is_empty():
		return {}
	var card := template.duplicate()
	card["id"] = instance_id
	return card


func _ids_to_cards(ids: Array) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id in ids:
		var card := _id_to_card(str(id))
		if not card.is_empty():
			cards.append(card)
	return cards


# --- Delta state encoding helpers ---

func _deep_equals(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _deep_equals(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _deep_equals(a[key], b[key]):
				return false
		return true
	return a == b


func _compute_delta(old_state: Dictionary, new_state: Dictionary) -> Dictionary:
	var delta := {}
	# Compare top-level fields (excluding "players" which is handled separately)
	for key in new_state:
		if key == "players":
			continue
		if not old_state.has(key) or not _deep_equals(old_state[key], new_state[key]):
			delta[key] = new_state[key]
	# Compare per-player state
	var old_players: Array = old_state.get("players", [])
	var new_players: Array = new_state.get("players", [])
	for i in range(new_players.size()):
		var new_pd: Dictionary = new_players[i]
		if i >= old_players.size():
			delta["p%d" % i] = new_pd
			continue
		var player_delta := _compute_player_delta(old_players[i], new_pd)
		if not player_delta.is_empty():
			delta["p%d" % i] = player_delta
	return delta


func _compute_player_delta(old_pd: Dictionary, new_pd: Dictionary) -> Dictionary:
	var delta := {}
	for key in new_pd:
		if key == "zones":
			# Compare each zone stack individually for sparse encoding
			var old_zones: Array = old_pd.get("zones", [])
			var new_zones: Array = new_pd.get("zones", [])
			var zones_delta := {}
			for z in range(maxi(old_zones.size(), new_zones.size())):
				var old_z: Array = old_zones[z] if z < old_zones.size() else []
				var new_z: Array = new_zones[z] if z < new_zones.size() else []
				if not _deep_equals(old_z, new_z):
					zones_delta[z] = new_z
			if not zones_delta.is_empty():
				delta["zones"] = zones_delta
		else:
			if not old_pd.has(key) or not _deep_equals(old_pd[key], new_pd[key]):
				delta[key] = new_pd[key]
	return delta


func _apply_delta(full_state: Dictionary, delta: Dictionary) -> Dictionary:
	var result := full_state.duplicate(true)
	# Apply top-level fields
	for key in delta:
		if key == "p0" or key == "p1":
			continue
		result[key] = delta[key]
	# Apply per-player deltas
	var players: Array = result.get("players", [ {}, {}])
	for i in range(2):
		var pkey := "p%d" % i
		if not delta.has(pkey):
			continue
		var pd: Dictionary = delta[pkey]
		if i >= players.size():
			players.append(pd)
			continue
		var existing: Dictionary = players[i]
		for field in pd:
			if field == "zones" and pd[field] is Dictionary:
				# Sparse zone update: merge individual zone indices
				var zone_delta: Dictionary = pd[field]
				var zones: Array = existing.get("zones", [])
				for z_key in zone_delta:
					var z_idx: int = int(z_key)
					if z_idx < zones.size():
						zones[z_idx] = zone_delta[z_key]
				existing["zones"] = zones
			else:
				existing[field] = pd[field]
	result["players"] = players
	return result


func _serialize_player_state(ps: PlayerState) -> Dictionary:
	var zone_ids: Array = []
	for zone_stack in ps.zones:
		zone_ids.append(_cards_to_ids(zone_stack))
	var strat_ids: Array = []
	for s in ps.strategy_zones:
		strat_ids.append(_card_to_id(s) if s is Dictionary else "")
	return {
		"player_id": ps.player_id,
		"monster_zone": ps.monster_zone,
		"rage": ps.rage,
		"current_monster": _card_to_id(ps.current_monster),
		"zones": zone_ids,
		"strategy_zones": strat_ids,
		"hand": _cards_to_ids(ps.hand),
		"hand_count": ps.hand.size(),
		"main_deck_count": ps.main_deck.size(),
		"discard_pile": _cards_to_ids(ps.discard_pile),
		"discard_pile_count": ps.discard_pile.size(),
		"has_invaded_this_turn": ps.has_invaded_this_turn,
		"has_played_monster_this_turn": ps.has_played_monster_this_turn,
		"monster_stack": _cards_to_ids(ps.monster_stack),
		"burst_monster": _card_to_id(ps.burst_monster),
		"pre_burst_monster": _card_to_id(ps.pre_burst_monster),
		"monster_deck": _cards_to_ids(ps.monster_deck),
	}


func _compute_state_hash(gs: GameState) -> int:
	## Hash shared (visible to both players) game state for desync detection.
	var parts: PackedStringArray = []
	parts.append("t%d" % gs.turn_number)
	parts.append("p%d" % gs.current_player_id)
	parts.append("ph%d" % int(gs.current_phase))
	for i in range(2):
		var ps: PlayerState = gs.players[i]
		parts.append("m%d:%d" % [i, ps.monster_zone])
		parts.append("r%d:%d" % [i, ps.rage])
		parts.append("d%d:%d" % [i, ps.main_deck.size()])
		parts.append("h%d:%d" % [i, ps.hand.size()])
		parts.append("dp%d:%d" % [i, ps.discard_pile.size()])
		# Hash zone top card IDs
		for z in range(8):
			var top := ps.get_zone_top_card(z)
			if not top.is_empty():
				parts.append("z%d_%d:%s" % [i, z, top.get("id", "")])
		# Hash strategy zones
		for s in range(ps.strategy_zones.size()):
			if not ps.strategy_zones[s].is_empty():
				parts.append("s%d_%d:%s" % [i, s, ps.strategy_zones[s].get("id", "")])
	return "".join(parts).hash()


func _compute_client_state_hash(turn_number: int, current_player_id: int, phase: int) -> int:
	## Client-side hash using reconstructed _client_players state.
	var parts: PackedStringArray = []
	parts.append("t%d" % turn_number)
	parts.append("p%d" % current_player_id)
	parts.append("ph%d" % phase)
	for i in range(2):
		var ps: PlayerState = _client_players[i]
		parts.append("m%d:%d" % [i, ps.monster_zone])
		parts.append("r%d:%d" % [i, ps.rage])
		parts.append("d%d:%d" % [i, ps.main_deck.size()])
		parts.append("h%d:%d" % [i, ps.hand.size()])
		parts.append("dp%d:%d" % [i, ps.discard_pile.size()])
		for z in range(8):
			var top := ps.get_zone_top_card(z)
			if not top.is_empty():
				parts.append("z%d_%d:%s" % [i, z, top.get("id", "")])
		for s in range(ps.strategy_zones.size()):
			if not ps.strategy_zones[s].is_empty():
				parts.append("s%d_%d:%s" % [i, s, ps.strategy_zones[s].get("id", "")])
	return "".join(parts).hash()


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
		"invade_cards": rules.get_discardable_cards_for_invade(player, opponent),
	}


# --- Multiplayer RPCs ---

## Client -> Host: submit an action
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_action(action_type: int, params_json: String) -> void:
	RpcLogger.log_receive("submit_action", 4 + params_json.length())
	if not NetworkManager.is_host() or not turn_manager:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	if sender_player_id != turn_manager.game_state.current_player_id:
		return # Not their turn
	_pending_interaction = {}

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
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_state(state_bytes: PackedByteArray) -> void:
	RpcLogger.log_receive("receive_state", state_bytes.size())
	if state_bytes.is_empty():
		return
	var decoded: Variant = bytes_to_var(state_bytes)
	if decoded == null or not decoded is Dictionary:
		push_warning("[STATE] bytes_to_var failed or returned non-Dictionary (size=%d)" % state_bytes.size())
		_request_resync_throttled()
		return
	var envelope: Dictionary = decoded
	if envelope.is_empty():
		return

	# Extract piggybacked log entries (tokens rendered in local locale)
	if envelope.has("log"):
		for entry in envelope["log"]:
			_log_tokens.append(entry)
			if log_output:
				log_output.append_text(_render_log_entry(entry) + "\n")
				log_output.scroll_to_line(log_output.get_line_count() - 1)

	# Play piggybacked sound events from host
	if envelope.has("sfx"):
		for sfx_name in envelope["sfx"]:
			SfxManager.play(str(sfx_name))

	var version: int = int(envelope.get("v", 0))
	var base_version: int = int(envelope.get("bv", -1))
	var payload: Dictionary = envelope.get("d", {})

	# Unwrap envelope: full state or delta
	var data: Dictionary
	if base_version == -1:
		# Full state
		data = payload
		_client_full_state = data.duplicate(true)
	else:
		if _client_state_version != base_version:
			push_warning("[DELTA] Base version mismatch: have %d, got bv=%d. Requesting resync." % [_client_state_version, base_version])
			_request_resync_throttled()
			return
		_client_full_state = _apply_delta(_client_full_state, payload)
		data = _client_full_state

	# Validate that the data has required fields before processing
	if not data.has("current_player_id") or not data.has("players"):
		push_warning("[STATE] Received state missing required fields — requesting resync")
		_request_resync_throttled()
		return

	# Track state version for desync detection
	if version > 0 and _client_state_version > 0 and version < _client_state_version:
		push_warning("[DESYNC] Received state version %d but already at %d — out-of-order delivery" % [version, _client_state_version])
	_client_state_version = version

	_client_current_player_id = int(data["current_player_id"])
	_client_turn_number = int(data.get("turn_number", 0))
	_client_phase = int(data.get("current_phase", 0)) as CardEnums.GamePhase
	_first_player_id = int(data.get("first_player_id", 0))


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
	if data.has("strategy_cp_modifiers"):
		_client_strategy_cp_mods = data["strategy_cp_modifiers"]
		for i in range(_client_strategy_cp_mods.size()):
			var arr: Array = _client_strategy_cp_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])
	if data.has("zone_rank_modifiers"):
		_client_zone_rank_mods = data["zone_rank_modifiers"]
		for i in range(_client_zone_rank_mods.size()):
			var arr: Array = _client_zone_rank_mods[i]
			for j in range(arr.size()):
				arr[j] = int(arr[j])
	if data.has("monster_cp_modifiers"):
		_client_monster_cp_mods = data["monster_cp_modifiers"]
		for j in range(_client_monster_cp_mods.size()):
			_client_monster_cp_mods[j] = int(_client_monster_cp_mods[j])

	# Reconstruct PlayerState objects
	var players_data: Array = data["players"]
	if players_data.size() < 2:
		push_warning("[STATE] players array too small: %d" % players_data.size())
		_request_resync_throttled()
		return
	for i in range(2):
		var pd: Dictionary = players_data[i]
		_client_players[i] = _dict_to_player_state(pd, i == local_player_id)
		# Store stats fields for disconnect reporting
		if pd.has("stats_deck_name"):
			_client_stats_deck_names[i] = str(pd["stats_deck_name"])
		if pd.has("stats_decklist"):
			_client_stats_decklists[i] = pd["stats_decklist"]
		if pd.has("stats_hand") and i != local_player_id:
			_client_stats_opponent_hand = pd["stats_hand"]

	# Stats timing from host
	if data.has("stats_elapsed_ms"):
		var arr: Array = data["stats_elapsed_ms"]
		_client_stats_elapsed_ms = [int(arr[0]), int(arr[1])] as Array[int]
	if data.has("stats_game_start_ms"):
		_client_stats_game_start_ms = int(data["stats_game_start_ms"])
	if data.has("stats_turn_start_ms"):
		_client_stats_turn_start_ms = int(data["stats_turn_start_ms"])

	# Apply monster color gradient and send player name on first state receive
	if not _client_gradients_applied:
		_client_gradients_applied = true
		for i in range(2):
			var board = player1_board if i == 0 else player2_board
			if not _client_players[i].current_monster.is_empty():
				board.apply_monster_gradient(_client_players[i].current_monster)
		RpcLogger.log_send("send_player_name", GameSettings.player_name.length())
		_rpc_send_player_name.rpc_id(NetworkManager.host_peer_id, GameSettings.player_name)

	# Sync player names from host (disambiguate from client's perspective)
	var host_names: Array = data.get("player_names", [])
	if host_names.size() == 2:
		var canonical: Array[String] = []
		for i in range(2):
			canonical.append(str(host_names[i]))
		GameLog.player_names = GameLog.disambiguate(canonical, local_player_id)
		for i in range(2):
			if i < _turn_tracker_headers.size():
				_turn_tracker_headers[i].text = GameLog.player_name(i)

	# Desync detection: compare state hash from host with locally reconstructed state
	if data.has("state_hash"):
		var host_hash: int = int(data["state_hash"])
		var local_hash: int = _compute_client_state_hash(
			int(data.get("turn_number", 0)),
			_client_current_player_id,
			int(data.get("current_phase", 0)))
		if host_hash != local_hash:
			push_warning("[DESYNC] State hash mismatch at version %d (turn %d, phase %d) — host=%d local=%d" % [
				_client_state_version,
				int(data.get("turn_number", 0)),
				int(data.get("current_phase", 0)),
				host_hash, local_hash])
			# Auto-resync if this was a delta (full state hash mismatch is a real desync)
			if base_version >= 0:
				push_warning("[DELTA] Hash mismatch after delta apply — requesting resync")
				_request_resync_throttled()

	# Update UI
	var client_phase := int(data["current_phase"]) as CardEnums.GamePhase
	var client_sub_phase: int = int(data.get("current_sub_phase", 0))
	_update_turn_tracker(_client_current_player_id, client_phase, client_sub_phase)
	_sync_boards()
	_update_hand_visibility(_client_current_player_id)


## Rate-limited resync request (client only). Prevents flooding the host with
## resync RPCs when multiple deltas fail in quick succession.
const RESYNC_COOLDOWN_MS: int = 2000
func _request_resync_throttled() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_resync_request_ms < RESYNC_COOLDOWN_MS:
		return # Too soon — skip this resync request
	_last_resync_request_ms = now
	RpcLogger.log_send("request_resync", 0)
	_rpc_request_resync.rpc_id(NetworkManager.host_peer_id)


## Client -> Host: request full state resend (delta base version mismatch or hash mismatch)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_resync() -> void:
	if not NetworkManager.is_host():
		return
	RpcLogger.log_receive("request_resync", 0)
	_last_sent_state = {}
	_last_sent_version = 0
	_broadcast_state()
	_flush_broadcast()
	# Re-send pending interaction if the host was waiting for client input
	if not _pending_interaction.is_empty():
		var method: String = _pending_interaction.get("method", "")
		var args: Array = _pending_interaction.get("args", [])
		var peer_id := multiplayer.get_remote_sender_id()
		if peer_id > 0:
			match method:
				"action_context":
					_rpc_receive_action_context.rpc_id(peer_id, args[0], args[1])
				"deck_search":
					_rpc_deck_search_requested.rpc_id(peer_id, args[0], args[1], args[2])
				"deck_arrange":
					_rpc_deck_arrange_requested.rpc_id(peer_id, args[0], args[1])
				"card_select":
					_rpc_card_select_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3], args[4])
				"hand_discard":
					_rpc_hand_discard_requested.rpc_id(peer_id, args[0])
				"hand_card_selection":
					_rpc_hand_card_selection_requested.rpc_id(peer_id, args[0], args[1], args[2])
				"zone_target":
					_rpc_zone_target_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3])
				"strategy_target":
					_rpc_strategy_target_requested.rpc_id(peer_id, args[0], args[1], args[2])
				"choice":
					_rpc_choice_requested.rpc_id(peer_id, args[0], args[1])
				"confirmation":
					_rpc_confirmation_requested.rpc_id(peer_id, args[0], args[1])
				"monster_rankup":
					_rpc_monster_rankup_requested.rpc_id(peer_id, args[0], args[1], args[2])
	elif turn_manager and not turn_manager.is_game_over:
		# Re-prompt whoever's turn it is
		# (_on_awaiting_action handles both host and client turn cases)
		var valid_actions := turn_manager.rules_engine.get_valid_actions(turn_manager.game_state)
		if not valid_actions.is_empty():
			_on_awaiting_action(valid_actions)


## Host -> Client: valid actions and playable indices
@rpc("any_peer", "call_remote", "reliable")
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
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_log(text: String) -> void:
	RpcLogger.log_receive("receive_log", text.length())
	_log_tokens.append(text)
	if log_output:
		log_output.append_text(text + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)


## Any peer -> Any peer: chat message
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_chat(sender_player_id: int, text: String) -> void:
	RpcLogger.log_receive("receive_chat", 4 + text.length())
	if sender_player_id < 0 or sender_player_id > 1:
		return
	var filtered := ChatFilter.filter(text)
	var token := {"type": "chat", "sender_id": sender_player_id, "text": filtered}
	_log_tokens.append(token)
	if log_output:
		log_output.append_text(GameLog.render(token) + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)
	_notify_mobile_log_chat()


## Host -> Client: deck search request (player must choose a card)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_requested(matching_json: String, all_json: String, prompt: String) -> void:
	RpcLogger.log_receive("deck_search_requested", matching_json.length() + all_json.length() + prompt.length())
	var matching_ids: Array = JSON.parse_string(matching_json)
	var all_ids: Array = JSON.parse_string(all_json)
	_show_deck_search(_ids_to_cards(matching_ids), _ids_to_cards(all_ids), prompt)


## Client -> Host: deck search resolved (player chose a card or skipped)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_resolved(selected_json: String) -> void:
	RpcLogger.log_receive("deck_search_resolved", selected_json.length())
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	var selected: Dictionary = {}
	if not selected_json.is_empty():
		selected = JSON.parse_string(selected_json)
		if selected == null:
			selected = {}
	turn_manager.action_handler.effect_handler.resolve_deck_search(selected)


## Host -> Client: deck arrange request (player must reorder/discard cards)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_arrange_requested(cards_json: String, prompt: String) -> void:
	RpcLogger.log_receive("deck_arrange_requested", cards_json.length() + prompt.length())
	if NetworkManager.is_host():
		return
	var card_ids: Array = JSON.parse_string(cards_json)
	_show_deck_arrange(_ids_to_cards(card_ids), prompt)


## Client -> Host: deck arrange resolved (player arranged cards)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_arrange_resolved(keep_json: String, discard_json: String) -> void:
	RpcLogger.log_receive("deck_arrange_resolved", keep_json.length() + discard_json.length())
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	var keep: Array[Dictionary] = []
	var discard: Array[Dictionary] = []
	var parsed_keep: Array = JSON.parse_string(keep_json)
	if parsed_keep:
		for c in parsed_keep:
			keep.append(c)
	var parsed_discard: Array = JSON.parse_string(discard_json)
	if parsed_discard:
		for c in parsed_discard:
			discard.append(c)
	turn_manager.action_handler.effect_handler.resolve_deck_arrange(keep, discard)


## Host -> Client: card select request (player must select N cards from pool)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_card_select_requested(matching_json: String, all_json: String, prompt: String, min_count: int, max_count: int) -> void:
	RpcLogger.log_receive("card_select_requested", matching_json.length() + all_json.length() + prompt.length())
	var matching_ids: Array = JSON.parse_string(matching_json)
	var all_ids: Array = JSON.parse_string(all_json)
	_show_card_select(_ids_to_cards(matching_ids), _ids_to_cards(all_ids), prompt, min_count, max_count)


## Client -> Host: card select resolved (player selected cards or skipped)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_card_select_resolved(selected_json: String) -> void:
	RpcLogger.log_receive("card_select_resolved", selected_json.length())
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	var selected: Array[Dictionary] = []
	if not selected_json.is_empty():
		var parsed: Array = JSON.parse_string(selected_json)
		if parsed:
			for id in parsed:
				selected.append({"id": str(id)})
	turn_manager.action_handler.effect_handler.resolve_card_select(selected)


## Host -> Client: hand card selection request (player must choose a card from hand)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_requested(indices_json: String, prompt: String, allow_skip: bool) -> void:
	RpcLogger.log_receive("hand_card_selection_requested", indices_json.length() + prompt.length() + 1)
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(indices_json)
	var valid_indices: Array[int] = []
	for v in parsed:
		valid_indices.append(int(v))
	if _client_current_player_id != local_player_id:
		SfxManager.play("action_required")
	_show_hand_card_selection(local_player_id, valid_indices, prompt, allow_skip)


## Client -> Host: hand card selection resolved
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_card_selection_resolved(hand_index: int) -> void:
	RpcLogger.log_receive("hand_card_selection_resolved", 4)
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	turn_manager.action_handler.effect_handler.resolve_hand_card_selection(hand_index)


## Host -> Client: confirmation request (draw / next turn)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_confirmation_requested(prompt: String, setting: String) -> void:
	RpcLogger.log_receive("confirmation_requested", prompt.length() + setting.length())
	if NetworkManager.is_host():
		return
	if _player_settings[local_player_id].get(setting, false):
		RpcLogger.log_send("confirmation_resolved", 0)
		_rpc_confirmation_resolved.rpc_id(NetworkManager.host_peer_id)
		return
	_show_confirmation(prompt)


## Client -> Host: confirmation resolved
@rpc("any_peer", "call_remote", "reliable")
func _rpc_confirmation_resolved() -> void:
	RpcLogger.log_receive("confirmation_resolved", 0)
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	turn_manager.confirm()


## Client -> Host: send player name
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_player_name(pname: String) -> void:
	RpcLogger.log_receive("send_player_name", pname.length())
	if not NetworkManager.is_host() or not turn_manager:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	if sender_player_id >= 0 and sender_player_id < 2:
		turn_manager.game_state.player_names[sender_player_id] = pname
		GameLog.player_names = GameLog.disambiguate(turn_manager.game_state.player_names, local_player_id)
		# Update host UI (disambiguation may affect both labels)
		for i in range(2):
			if i < _turn_tracker_headers.size():
				_turn_tracker_headers[i].text = GameLog.player_name(i)
		# Re-broadcast so client gets the updated names
		_broadcast_state()


## Host -> Client: hand discard request (player must choose cards to discard)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_requested(discard_count: int) -> void:
	RpcLogger.log_receive("hand_discard_requested", 4)
	if NetworkManager.is_host():
		return # Safety: this RPC is only for clients
	if _client_current_player_id != local_player_id:
		SfxManager.play("action_required")
	_show_hand_discard_selection(local_player_id, discard_count)


## Client -> Host: hand discard resolved (player chose cards)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hand_discard_resolved(indices_json: String) -> void:
	RpcLogger.log_receive("hand_discard_resolved", indices_json.length())
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	var parsed: Array = JSON.parse_string(indices_json)
	var hand_indices: Array[int] = []
	for v in parsed:
		hand_indices.append(int(v))
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	turn_manager.action_handler.effect_handler.resolve_hand_discard(sender_player_id, hand_indices)


## Host -> Client: zone target request (player must choose a zone)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_zone_target_requested(target_player_id: int, zones_json: String, prompt: String, allow_skip: bool) -> void:
	RpcLogger.log_receive("zone_target_requested", 4 + zones_json.length() + prompt.length() + 1)
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
	RpcLogger.log_receive("zone_target_resolved", 4)
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	turn_manager.action_handler.effect_handler.resolve_zone_target(zone_index)


## Host -> Client: strategy target request (player must choose a strategy zone)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_strategy_target_requested(target_player_id: int, indices_json: String, prompt: String) -> void:
	RpcLogger.log_receive("strategy_target_requested", 4 + indices_json.length() + prompt.length())
	if NetworkManager.is_host():
		return
	var parsed: Array = JSON.parse_string(indices_json)
	var valid_indices: Array[int] = []
	for v in parsed:
		valid_indices.append(int(v))
	_show_strategy_target_selection(local_player_id, target_player_id, valid_indices, prompt)


## Client -> Host: strategy target resolved (player chose a strategy zone)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_strategy_target_resolved(strategy_index: int) -> void:
	RpcLogger.log_receive("strategy_target_resolved", 4)
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	turn_manager.action_handler.effect_handler.resolve_strategy_target(strategy_index)


## Host -> Client: choice request (player must choose ability order)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice_requested(options_json: String, prompt: String) -> void:
	RpcLogger.log_receive("choice_requested", options_json.length() + prompt.length())
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
	RpcLogger.log_receive("choice_resolved", 4)
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	turn_manager.action_handler.effect_handler.resolve_choice(index)


## Host -> Client: prompt monster rank-up selection
@rpc("any_peer", "call_remote", "reliable")
func _rpc_monster_rankup_requested(monsters_json: String, indices_json: String, prompt: String) -> void:
	RpcLogger.log_receive("monster_rankup_requested", monsters_json.length() + indices_json.length() + prompt.length())
	if NetworkManager.is_host():
		return
	var monster_ids: Array = JSON.parse_string(monsters_json)
	var monsters: Array[Dictionary] = _ids_to_cards(monster_ids)
	var parsed_indices: Array = JSON.parse_string(indices_json)
	var valid_indices: Array[int] = []
	for v in parsed_indices:
		valid_indices.append(int(v))
	SfxManager.play("action_required")
	_show_monster_rankup_selection(local_player_id, monsters, valid_indices, prompt)


## Client -> Host: resolve monster rank-up selection
@rpc("any_peer", "call_remote", "reliable")
func _rpc_monster_rankup_resolved(index: int) -> void:
	RpcLogger.log_receive("monster_rankup_resolved", 4)
	if not NetworkManager.is_host() or not turn_manager:
		return
	_pending_interaction = {}
	turn_manager.action_handler.resolve_monster_rankup(index)


## Host -> Client: highlight a zone card during effect resolution
@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_zone_highlighted(pid: int, zone_index: int) -> void:
	RpcLogger.log_receive("effect_zone_highlighted", 8)
	if NetworkManager.is_host():
		return
	_apply_zone_highlight(pid, zone_index, true)


## Host -> Client: unhighlight a zone card after effect resolution
@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_zone_unhighlighted(pid: int, zone_index: int) -> void:
	RpcLogger.log_receive("effect_zone_unhighlighted", 8)
	if NetworkManager.is_host():
		return
	_apply_zone_highlight(pid, zone_index, false)


## Host -> Client: highlight the source card of an active effect
@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_card_highlighted(pid: int, card_id: String) -> void:
	RpcLogger.log_receive("effect_card_highlighted", 4 + card_id.length())
	if NetworkManager.is_host():
		return
	_apply_card_highlight(pid, card_id, true)


## Host -> Client: unhighlight the source card after effect resolves
@rpc("any_peer", "call_remote", "reliable")
func _rpc_effect_card_unhighlighted(pid: int, card_id: String) -> void:
	RpcLogger.log_receive("effect_card_unhighlighted", 4 + card_id.length())
	if NetworkManager.is_host():
		return
	_apply_card_highlight(pid, card_id, false)


## Host -> Client: game over
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_game_ended(winner_id: int, reason_key: String) -> void:
	RpcLogger.log_receive("receive_game_ended", 4 + reason_key.length())
	SfxManager.play("game_win" if winner_id == local_player_id else "game_lose")
	_action_pending = false
	_game_ended_by_disconnect = false
	_rematch_requested = false
	_opponent_rematch_requested = false
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		var reason_text := GameLog.render_reason(reason_key)
		win_label.text = tr("STR_GB_WINS_FMT").replace("{NAME}", GameLog.player_name(winner_id)) + "\n" + reason_text
	btn_rematch.visible = true
	btn_rematch.disabled = false
	btn_rematch.text = tr("STR_GB_REMATCH")
	_populate_rematch_deck_select()
	_disable_all_buttons()
	RpcLogger.print_summary()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_replay(compressed: PackedByteArray) -> void:
	RpcLogger.log_receive("receive_replay", compressed.size())
	var json_bytes := compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if json_bytes.is_empty():
		push_warning("[Replay] Failed to decompress replay data")
		return
	var json := JSON.new()
	if json.parse(json_bytes.get_string_from_utf8()) != OK:
		push_warning("[Replay] Failed to parse replay JSON")
		return
	var replay := ReplayData.new()
	replay.from_dict(json.data)
	var ver := ReplayData._get_game_version()
	var fname := "replay_%s.json" % replay.timestamp.replace(" ", "_").replace(":", "").replace("-", "")
	var path := ReplayData.get_version_recent_dir(ver) + fname
	var err := ReplayData.save_to_file(replay, path)
	if err == OK:
		print("[Replay] Client saved replay to %s (%d snapshots)" % [path, replay.snapshots.size()])
		ReplayData.prune_recent(ver)
	else:
		push_warning("[Replay] Client failed to save replay (error %d)" % err)


# --- Multiplayer: State deserialization (client) ---

func _dict_to_player_state(data: Dictionary, is_local: bool) -> PlayerState:
	var ps := PlayerState.new(int(data["player_id"]))
	ps.monster_zone = int(data["monster_zone"])
	ps.rage = int(data["rage"])
	ps.current_monster = _id_to_card(str(data.get("current_monster", "")))
	ps.has_invaded_this_turn = data.get("has_invaded_this_turn", false)
	ps.has_played_monster_this_turn = data.get("has_played_monster_this_turn", false)
	for m in data.get("monster_stack", []):
		var card := _id_to_card(str(m))
		if not card.is_empty():
			ps.monster_stack.append(card)
	ps.burst_monster = _id_to_card(str(data.get("burst_monster", "")))
	ps.pre_burst_monster = _id_to_card(str(data.get("pre_burst_monster", "")))

	# Zones: each zone is an array of card IDs
	var zones_data: Array = data.get("zones", [])
	for i in range(mini(zones_data.size(), 8)):
		var zone_stack: Array[Dictionary] = []
		for card_id in zones_data[i]:
			var card := _id_to_card(str(card_id))
			if not card.is_empty():
				zone_stack.append(card)
		ps.zones[i] = zone_stack

	# Strategy zones (may be 2 or 3): each is a card ID string
	var sz_data: Array = data.get("strategy_zones", [])
	if sz_data.size() > ps.strategy_zones.size():
		ps.strategy_zones.resize(sz_data.size())
		ps.strategy_zone_turn_placed.resize(sz_data.size())
	for i in range(sz_data.size()):
		ps.strategy_zones[i] = _id_to_card(str(sz_data[i]))

	# Hand: IDs for local player, face-down placeholders for opponent
	if is_local and data.has("hand"):
		ps.hand.assign(_ids_to_cards(data["hand"]))
	else:
		var count: int = int(data.get("hand_count", 0))
		ps.hand.clear()
		for j in range(count):
			ps.hand.append({"face_down": true, "id": "opponent_%d" % j})

	# Monster deck: IDs for local player, placeholder count for opponent
	if is_local and data.has("monster_deck"):
		ps.monster_deck.assign(_ids_to_cards(data["monster_deck"]))
	else:
		var md_count: int = int(data.get("monster_deck_count", 0))
		ps.monster_deck.resize(md_count)
		for j in range(md_count):
			ps.monster_deck[j] = {}

	# Deck: only counts needed for display labels
	var deck_count: int = int(data.get("main_deck_count", 0))
	ps.main_deck.resize(deck_count)
	for j in range(deck_count):
		ps.main_deck[j] = {}

	# Discard pile: card IDs
	if data.has("discard_pile"):
		ps.discard_pile.assign(_ids_to_cards(data["discard_pile"]))
	else:
		var discard_count: int = int(data.get("discard_pile_count", 0))
		ps.discard_pile.resize(discard_count)
		for j in range(discard_count):
			ps.discard_pile[j] = {}

	return ps


# --- Stats upload ---

func _upload_stats(winner_id: int, reason: String, is_disconnect: bool) -> void:
	# Only upload for online games, and only once per match
	if _stats_uploaded:
		return
	if NetworkManager.mode != NetworkManager.Mode.ONLINE_HOST and NetworkManager.mode != NetworkManager.Mode.ONLINE_CLIENT:
		return
	# Host is primary reporter; client only reports on disconnect
	if not is_disconnect and not NetworkManager.is_host():
		return
	_stats_uploaded = true

	# Host uses turn_manager directly; client reconstructs from synced state
	var gs: GameState
	if turn_manager:
		gs = turn_manager.game_state
	else:
		gs = GameState.new()
		gs.players = _client_players
		gs.current_player_id = _client_current_player_id
		gs.turn_number = _client_turn_number
		gs.current_phase = _client_phase
		gs.player_names = Array(GameLog.player_names) as Array[String]
		# Restore opponent's hand from stats snapshot
		var opponent_id := 1 - local_player_id
		if not _client_stats_opponent_hand.is_empty():
			gs.players[opponent_id].hand.assign(_ids_to_cards(_client_stats_opponent_hand))
		# Populate DecklistManager with synced decklist data
		for i in range(2):
			if _client_stats_decklists[i] != null and not DecklistManager.has_player_deck(i):
				var dl: Dictionary = _client_stats_decklists[i]
				DecklistManager._player_decks[i] = {
					"deck_name": _client_stats_deck_names[i],
					"monster_deck": dl.get("monster_deck", []),
					"main_entries": dl.get("main_entries", []),
				}
		# Use host-synced elapsed times
		_player_elapsed_ms = _client_stats_elapsed_ms.duplicate()
		_game_start_time_ms = _client_stats_game_start_ms
		_turn_start_time_ms = _client_stats_turn_start_ms

	# Finalize active player's elapsed time
	if _turn_start_time_ms > 0:
		var now := Time.get_ticks_msec()
		var active_pid := gs.current_player_id
		_player_elapsed_ms[active_pid] += now - _turn_start_time_ms
	var total_elapsed := Time.get_ticks_msec() - _game_start_time_ms if _game_start_time_ms > 0 else 0
	StatsUploader.upload_game_result(
		gs,
		winner_id,
		reason,
		_first_player_id,
		_player_elapsed_ms,
		total_elapsed,
		is_disconnect,
	)


# --- Multiplayer: Disconnect handling ---

func _on_opponent_disconnected(_peer_id: int) -> void:
	_disable_all_buttons()
	# If the game was already over (normal end), just hide the rematch button
	if end_game_panel.visible:
		btn_rematch.visible = false
		_rematch_deck_select.visible = false
		return

	var is_online := NetworkManager.mode in [NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT]

	# LAN games: immediate disconnect (no reconnect possible)
	if not is_online:
		_handle_final_disconnect()
		return

	# Online HOST side: show overlay and wait for reconnect
	if NetworkManager.is_host():
		_on_log_message(GameLog.opponent_disconnected_waiting())
		_waiting_for_reconnect = true
		_reconnect_current_start_ms = Time.get_ticks_msec()
		_reconnect_label.text = tr("STR_GB_OPPONENT_DISCONNECTED_WAIT")
		_reconnect_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(int(RECONNECT_CLAIM_WIN_SECONDS)))
		_reconnect_claim_btn.visible = false
		_reconnect_overlay.visible = true
		return

	# Online CLIENT side: attempt to reconnect to the host via relay
	_on_log_message(GameLog.connection_lost_reconnecting())
	_waiting_for_reconnect = true
	_reconnect_current_start_ms = Time.get_ticks_msec()
	_reconnect_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
	_reconnect_timer_label.text = ""
	_reconnect_claim_btn.visible = false
	_reconnect_menu_btn.visible = true
	_reconnect_overlay.visible = true
	if not _reconnect_attempting:
		_attempt_client_reconnect()


func _handle_final_disconnect() -> void:
	_game_ended_by_disconnect = true
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		win_label.text = tr("STR_GB_OPPONENT_DISCONNECTED")
	btn_rematch.visible = false
	_upload_stats(local_player_id, "Opponent disconnected", true)


func _attempt_client_reconnect() -> void:
	_reconnect_attempting = true
	var room_code := NetworkManager.get_game_code()
	while _waiting_for_reconnect and is_inside_tree():
		_reconnect_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
		var err: Error = await NetworkManager.attempt_reconnect(room_code)
		if err == OK:
			# Reconnected — clear overlay and reset ALL client delta state
			_reconnect_cumulative_seconds += (Time.get_ticks_msec() - _reconnect_current_start_ms) / 1000.0
			_waiting_for_reconnect = false
			_reconnect_attempting = false
			_reconnect_overlay.visible = false
			# Reset delta state so next broadcast is treated as full state
			_client_full_state = {}
			_client_state_version = 0
			_last_resync_request_ms = 0
			_action_pending = false
			_on_log_message(GameLog.reconnected())
			# Wait a frame for the connection to stabilize before sending RPCs
			await get_tree().process_frame
			if not is_inside_tree():
				return
			# Re-send player name and request full state resync from host.
			# The host already tried to resync during the relay handshake,
			# but those RPCs may have arrived before the connection was fully ready.
			RpcLogger.log_send("send_player_name", GameSettings.player_name.length())
			_rpc_send_player_name.rpc_id(NetworkManager.host_peer_id, GameSettings.player_name)
			RpcLogger.log_send("request_resync", 0)
			_rpc_request_resync.rpc_id(NetworkManager.host_peer_id)
			return
		# Failed — wait 2s and retry
		_reconnect_label.text = tr("STR_GB_CONNECTION_LOST_RETRYING")
		await get_tree().create_timer(2.0).timeout
	_reconnect_attempting = false


func _on_opponent_reconnected(_peer_id: int) -> void:
	if not _waiting_for_reconnect:
		return

	# Accumulate elapsed wait time
	_reconnect_cumulative_seconds += (Time.get_ticks_msec() - _reconnect_current_start_ms) / 1000.0
	_waiting_for_reconnect = false
	_reconnect_overlay.visible = false

	if not end_game_panel.visible:
		# Game is still in progress — resync the client after a brief delay
		# to let the connection stabilize before sending large state RPCs
		_on_log_message(GameLog.opponent_reconnected())
		await get_tree().create_timer(0.2).timeout
		if not is_inside_tree():
			return
		_resync_reconnected_client()
	else:
		# Game ended while they were gone (win was claimed) — re-send result
		await get_tree().create_timer(0.2).timeout
		if not is_inside_tree():
			return
		RpcLogger.log_send("receive_game_ended", 4 + len("STR_LOG_REASON_OPPONENT_DISCONNECTED"))
		_rpc_receive_game_ended.rpc(local_player_id, "STR_LOG_REASON_OPPONENT_DISCONNECTED")
		# Show rematch button now that opponent is back
		btn_rematch.visible = true
		btn_rematch.disabled = false
		btn_rematch.text = tr("STR_GB_REMATCH")
		_game_ended_by_disconnect = false
		_populate_rematch_deck_select()


func _resync_reconnected_client() -> void:
	# Force full state broadcast by clearing last sent state
	_last_sent_state = {}
	_last_sent_version = 0
	_broadcast_state()
	_flush_broadcast()

	# Re-send pending interaction if the host was waiting for client input
	if not _pending_interaction.is_empty():
		var method: String = _pending_interaction.get("method", "")
		var args: Array = _pending_interaction.get("args", [])
		var peer_id := _get_client_peer_id()
		if peer_id > 0:
			match method:
				"action_context":
					RpcLogger.log_send("receive_action_context", args[0].length() + args[1].length())
					_rpc_receive_action_context.rpc_id(peer_id, args[0], args[1])
				"deck_search":
					RpcLogger.log_send("deck_search_requested", args[0].length() + args[1].length() + args[2].length())
					_rpc_deck_search_requested.rpc_id(peer_id, args[0], args[1], args[2])
				"deck_arrange":
					RpcLogger.log_send("deck_arrange_requested", args[0].length() + args[1].length())
					_rpc_deck_arrange_requested.rpc_id(peer_id, args[0], args[1])
				"card_select":
					RpcLogger.log_send("card_select_requested", args[0].length() + args[1].length() + args[2].length())
					_rpc_card_select_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3], args[4])
				"hand_discard":
					RpcLogger.log_send("hand_discard_requested", 4)
					_rpc_hand_discard_requested.rpc_id(peer_id, args[0])
				"hand_card_selection":
					RpcLogger.log_send("hand_card_selection_requested", args[0].length() + args[1].length() + 1)
					_rpc_hand_card_selection_requested.rpc_id(peer_id, args[0], args[1], args[2])
				"zone_target":
					RpcLogger.log_send("zone_target_requested", 4 + args[1].length() + args[2].length() + 1)
					_rpc_zone_target_requested.rpc_id(peer_id, args[0], args[1], args[2], args[3])
				"strategy_target":
					RpcLogger.log_send("strategy_target_requested", 4 + args[1].length() + args[2].length())
					_rpc_strategy_target_requested.rpc_id(peer_id, args[0], args[1], args[2])
				"choice":
					RpcLogger.log_send("choice_requested", args[0].length() + args[1].length())
					_rpc_choice_requested.rpc_id(peer_id, args[0], args[1])
				"confirmation":
					RpcLogger.log_send("confirmation_requested", args[0].length() + args[1].length())
					_rpc_confirmation_requested.rpc_id(peer_id, args[0], args[1])
				"monster_rankup":
					RpcLogger.log_send("monster_rankup_requested", args[0].length() + args[1].length() + args[2].length())
					_rpc_monster_rankup_requested.rpc_id(peer_id, args[0], args[1], args[2])
	elif turn_manager and not turn_manager.is_game_over:
		# No pending interaction — re-prompt whoever's turn it is
		# (_on_awaiting_action handles both host and client turn cases)
		var valid_actions := turn_manager.rules_engine.get_valid_actions(turn_manager.game_state)
		if not valid_actions.is_empty():
			_on_awaiting_action(valid_actions)


func _get_client_peer_id() -> int:
	for peer_id in NetworkManager.peer_player_map:
		if peer_id != 1 and NetworkManager.peer_player_map[peer_id] != local_player_id:
			return peer_id
	return -1


func _on_reconnect_claim_win() -> void:
	_waiting_for_reconnect = false
	_reconnect_overlay.visible = false
	# End the game with local player as winner
	_game_ended_by_disconnect = true
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		win_label.text = tr("STR_GB_YOU_WIN_OPP_DISC")
	btn_rematch.visible = false
	_disable_all_buttons()
	_upload_stats(local_player_id, "Opponent disconnected", true)
	_on_log_message(GameLog.claimed_win_disconnect())
