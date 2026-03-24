extends Node3D

## VR game board — orchestrates the 3D card game experience.
## Prototype: wires directly to TurnManager for solo/bot play.
## Future: will use GameFlowController for shared logic with 2D game_board.gd.

var turn_manager: TurnManager
var bot_player: BotPlayer

# Board references
var environment: Node3D
var local_board: VRPlayerBoard3D
var opponent_board: VRPlayerBoard3D
var hand_display: Node3D  # Will be VRHandDisplay3D when implemented

# XR nodes
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D

# UI
var action_label: Label3D
var phase_label: Label3D
var log_label: Label3D

# Game state
var local_player_id: int = 0
var _valid_actions: Array = []
var _log_lines: PackedStringArray = []
const MAX_LOG_LINES := 8


func _ready() -> void:
	# Stop menu music for VR
	MusicManager.set_volume(0)

	print("[VRGameBoard3D] Setting up scene...")
	_setup_xr()
	print("[VRGameBoard3D] XR done")
	_setup_xr_rig()
	print("[VRGameBoard3D] XR rig done")
	_setup_environment()
	print("[VRGameBoard3D] Environment done")
	_setup_boards()
	print("[VRGameBoard3D] Boards done")
	_setup_hand_display()
	print("[VRGameBoard3D] Hand display done")
	_setup_ui()
	print("[VRGameBoard3D] UI done")

	# Defer game setup to next frame so the visual scene renders first
	call_deferred("_setup_game")


func _setup_xr() -> void:
	# Use godot-xr-tools StartXR for reliable XR initialization
	var start_xr_scene: PackedScene = load("res://addons/godot-xr-tools/xr/start_xr.tscn")
	if start_xr_scene:
		var start_xr: Node = start_xr_scene.instantiate()
		start_xr.name = "StartXR"
		add_child(start_xr)
		print("[VRGameBoard3D] StartXR node added")
	else:
		push_error("[VRGameBoard3D] Failed to load StartXR scene")


func _setup_xr_rig() -> void:
	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin3D"

	xr_camera = XRCamera3D.new()
	xr_camera.name = "XRCamera3D"
	xr_origin.add_child(xr_camera)

	left_controller = XRController3D.new()
	left_controller.name = "LeftController"
	left_controller.tracker = &"left_hand"
	xr_origin.add_child(left_controller)

	right_controller = XRController3D.new()
	right_controller.name = "RightController"
	right_controller.tracker = &"right_hand"
	xr_origin.add_child(right_controller)

	# Add laser pointer to right controller
	var pointer_script := preload("res://scenes/vr/vr_pointer.gd")
	var pointer := Node3D.new()
	pointer.name = "Pointer"
	pointer.set_script(pointer_script)
	right_controller.add_child(pointer)

	# Connect pointer signals
	pointer.pointed_at_slot.connect(_on_pointer_slot)
	pointer.pointed_at_card.connect(_on_pointer_card)
	pointer.pointed_at_nothing.connect(_on_pointer_nothing)

	# Position player at table edge, seated height
	# Table is at (0, 0.75, 0), player sits at +Z side looking toward -Z
	xr_origin.position = Vector3(0, 0, 0.55)

	add_child(xr_origin)


func _setup_environment() -> void:
	var env_scene := preload("res://scenes/vr/VREnvironment.tscn")
	environment = env_scene.instantiate()
	add_child(environment)


func _setup_boards() -> void:
	var surface_y: float = environment.get_table_surface_y()

	# Local player's board (near side of table, +Z)
	local_board = VRPlayerBoard3D.new()
	local_board.name = "LocalBoard"
	local_board.player_id = local_player_id
	local_board.is_opponent = false
	local_board.position = Vector3(0, surface_y, 0.15)
	local_board.zone_slot_clicked.connect(_on_zone_clicked)
	add_child(local_board)

	# Opponent's board (far side of table, -Z)
	opponent_board = VRPlayerBoard3D.new()
	opponent_board.name = "OpponentBoard"
	opponent_board.player_id = 1 - local_player_id
	opponent_board.is_opponent = true
	opponent_board.position = Vector3(0, surface_y, -0.15)
	# Rotate opponent board 180 degrees so it faces the player
	opponent_board.rotation.y = PI
	add_child(opponent_board)


func _setup_hand_display() -> void:
	var surface_y: float = environment.get_table_surface_y()

	# Simple hand display: cards fanned in front of the player
	hand_display = Node3D.new()
	hand_display.name = "HandDisplay"
	hand_display.position = Vector3(0, surface_y + 0.01, 0.35)
	add_child(hand_display)


func _setup_ui() -> void:
	var surface_y: float = environment.get_table_surface_y()

	# Phase label (floating above table center)
	phase_label = Label3D.new()
	phase_label.name = "PhaseLabel"
	phase_label.text = "Starting..."
	phase_label.font_size = 48
	phase_label.pixel_size = 0.001
	phase_label.position = Vector3(0, surface_y + 0.15, 0)
	phase_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	phase_label.modulate = Color(1.0, 0.95, 0.8)
	phase_label.outline_modulate = Color.BLACK
	phase_label.outline_size = 6
	add_child(phase_label)

	# Action label (shows available actions)
	action_label = Label3D.new()
	action_label.name = "ActionLabel"
	action_label.text = ""
	action_label.font_size = 36
	action_label.pixel_size = 0.001
	action_label.position = Vector3(-0.4, surface_y + 0.1, 0.3)
	action_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	action_label.modulate = Color.WHITE
	action_label.outline_modulate = Color.BLACK
	action_label.outline_size = 4
	add_child(action_label)

	# Game log (right side)
	log_label = Label3D.new()
	log_label.name = "LogLabel"
	log_label.text = ""
	log_label.font_size = 24
	log_label.pixel_size = 0.0008
	log_label.position = Vector3(0.45, surface_y + 0.1, 0.2)
	log_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	log_label.modulate = Color(0.8, 0.8, 0.8)
	log_label.outline_modulate = Color.BLACK
	log_label.outline_size = 3
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(log_label)


func _setup_game() -> void:
	print("[VRGameBoard3D] Setting up game...")
	turn_manager = TurnManager.new()
	turn_manager.setup(CardData)
	print("[VRGameBoard3D] TurnManager setup done")

	# Set player names
	turn_manager.game_state.player_names[0] = GameSettings.player_name
	turn_manager.game_state.player_names[1] = "Bot"

	# Connect turn manager signals
	turn_manager.phase_started.connect(_on_phase_started)
	turn_manager.phase_ended.connect(_on_phase_ended)
	turn_manager.awaiting_player_action.connect(_on_awaiting_action)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.game_ended.connect(_on_game_ended)
	turn_manager.log_message.connect(_on_log_message)
	turn_manager.confirmation_requested.connect(_on_confirmation_requested)

	# Connect action handler signals
	turn_manager.action_handler.cards_drawn.connect(_on_cards_drawn)
	turn_manager.action_handler.battle_card_played.connect(_on_battle_card_played)
	turn_manager.action_handler.strategy_card_played.connect(_on_strategy_card_played)
	turn_manager.action_handler.rage_gained.connect(_on_rage_gained)
	turn_manager.action_handler.monster_advanced.connect(_on_monster_advanced)

	# Connect effect handler signals
	turn_manager.action_handler.effect_handler.choice_requested.connect(_on_choice_requested)
	turn_manager.action_handler.effect_handler.deck_search_requested.connect(_on_deck_search_requested)
	turn_manager.action_handler.effect_handler.hand_discard_requested.connect(_on_hand_discard_requested)
	turn_manager.action_handler.effect_handler.log_message.connect(_on_log_message)

	# Connect player state change signals for live board sync
	for player in turn_manager.game_state.players:
		player.hand_changed.connect(_sync_boards)
		player.zones_changed.connect(_sync_boards)
		player.rage_changed.connect(_sync_boards.unbind(1))
		player.monster_changed.connect(_sync_boards)
		player.discard_changed.connect(_sync_boards)
		player.deck_changed.connect(_sync_boards)
		player.strategy_zones_changed.connect(_sync_boards)

	# Setup bot
	_setup_bot()

	# Initial sync
	_sync_boards()

	# Start game — player 0 goes first for prototype
	turn_manager.start_game(0)


func _setup_bot() -> void:
	bot_player = BotPlayer.new()
	bot_player.bot_player_id = 1
	bot_player.game_state = turn_manager.game_state
	bot_player.rules_engine = turn_manager.rules_engine
	bot_player.turn_manager = turn_manager
	bot_player.action_handler = turn_manager.action_handler
	bot_player.effect_handler = turn_manager.action_handler.effect_handler
	bot_player.scene_tree = Engine.get_main_loop() as SceneTree

	# Connect bot to decision signals
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


func _sync_boards() -> void:
	var gs := turn_manager.game_state
	var p0 := gs.players[local_player_id]
	var p1 := gs.players[1 - local_player_id]

	local_board.sync_to_state(p0)
	opponent_board.sync_to_state(p1)
	_sync_hand_display(p0)


func _sync_hand_display(player: PlayerState) -> void:
	# Clear existing hand cards
	for child in hand_display.get_children():
		child.queue_free()

	if player.hand.is_empty():
		return

	# Fan cards in an arc
	var card_scene := preload("res://scenes/vr/VRCard3D.tscn")
	var card_count := player.hand.size()
	var total_width := mini(card_count, 10) * 0.04  # 40mm spacing, max 10 visible
	var start_x := -total_width / 2.0

	for i in range(card_count):
		var vr_card: VRCard3D = card_scene.instantiate()
		vr_card.set_card_data_dict(player.hand[i])
		# Arrange in a slight arc
		var t := float(i) / maxf(card_count - 1, 1)
		var x := start_x + t * total_width
		var z := -0.02 * sin(t * PI)  # Slight arc
		var y := 0.001 * i  # Stack slightly so they don't z-fight
		vr_card.position = Vector3(x, y, z)
		# Slight tilt based on position
		vr_card.rotation.y = lerp(0.1, -0.1, t)
		hand_display.add_child(vr_card)

		# Connect card click for selection
		vr_card.card_clicked.connect(_on_hand_card_clicked.bind(i))


func _on_hand_card_clicked(_card: VRCard3D, index: int) -> void:
	# For prototype: auto-submit the card as action based on current valid actions
	if _valid_actions.is_empty():
		return

	var player := turn_manager.game_state.players[local_player_id]
	if index >= player.hand.size():
		return

	var card_data := player.hand[index]

	# Try to find a matching action for this card
	for action in _valid_actions:
		if action == CardEnums.ActionType.PLAY_BATTLE:
			if card_data.get("card_type") == CardEnums.CardType.BATTLE:
				# Find first valid zone
				var valid := turn_manager.rules_engine.get_valid_battle_zones(
					turn_manager.game_state, local_player_id, card_data)
				if not valid.is_empty():
					turn_manager.action_handler.execute_play_battle(
						turn_manager.game_state, local_player_id, index, valid[0])
					return
		elif action == CardEnums.ActionType.GAIN_RAGE:
			if card_data.get("card_type") == CardEnums.CardType.BATTLE:
				turn_manager.action_handler.execute_gain_rage(
					turn_manager.game_state, local_player_id, index)
				return


# --- Signal handlers ---

func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	var phase_names := {
		CardEnums.GamePhase.START: "Start Phase",
		CardEnums.GamePhase.MAIN: "Main Phase",
		CardEnums.GamePhase.COUNTER: "Counter Phase",
		CardEnums.GamePhase.END: "End Phase",
	}
	phase_label.text = phase_names.get(phase, "Phase %d" % phase)
	_sync_boards()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()


func _on_turn_started(player_id: int) -> void:
	var name_str := turn_manager.game_state.player_names[player_id]
	phase_label.text = "%s's Turn" % name_str
	_sync_boards()


func _on_awaiting_action(valid_actions: Array) -> void:
	_valid_actions = valid_actions
	var current_pid := turn_manager.game_state.current_player_id

	if current_pid != local_player_id:
		action_label.text = "Opponent's turn..."
		return

	# Build action label
	var action_names := []
	for action in valid_actions:
		match action:
			CardEnums.ActionType.PLAY_BATTLE:
				action_names.append("Play Battle")
			CardEnums.ActionType.PLAY_STRATEGY:
				action_names.append("Play Strategy")
			CardEnums.ActionType.GAIN_RAGE:
				action_names.append("Gain Rage")
			CardEnums.ActionType.PLAY_MONSTER:
				action_names.append("Play Monster")
			CardEnums.ActionType.INVADE:
				action_names.append("Invade")
			CardEnums.ActionType.END_MAIN:
				action_names.append("End Main")
			CardEnums.ActionType.PASS:
				action_names.append("Pass")
	action_label.text = "Actions:\n" + "\n".join(action_names)
	_sync_boards()


func _on_game_ended(winner_id: int, reason: String) -> void:
	var winner_name := turn_manager.game_state.player_names[winner_id]
	phase_label.text = "%s wins!\n%s" % [winner_name, reason]
	action_label.text = ""
	_sync_boards()


func _on_log_message(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG_LINES)
	log_label.text = "\n".join(_log_lines)


func _on_confirmation_requested(_prompt: String, _setting: String) -> void:
	# Auto-confirm for local player; bot handles its own confirmations
	if turn_manager.game_state.current_player_id == local_player_id:
		turn_manager.confirm()


func _on_cards_drawn(player_id: int, _count: int) -> void:
	if player_id == local_player_id:
		_sync_boards()


func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone: int) -> void:
	_sync_boards()


func _on_strategy_card_played(_player_id: int, _card: Dictionary, _strategy_index: int) -> void:
	_sync_boards()


func _on_rage_gained(_player_id: int, _new_rage: int) -> void:
	_sync_boards()


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	_sync_boards()


func _on_choice_requested(player_id: int, _options: Array[String], _prompt: String) -> void:
	if player_id != local_player_id:
		return  # Bot handles its own choices
	# Auto-select first choice for prototype
	turn_manager.action_handler.effect_handler.resolve_choice(0)


func _on_deck_search_requested(player_id: int, _matching_cards: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String) -> void:
	if player_id != local_player_id:
		return  # Bot handles its own searches
	# Auto-skip for prototype
	turn_manager.action_handler.effect_handler.resolve_deck_search(null)


func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if player_id != local_player_id:
		return  # Bot handles its own discards
	# Auto-discard first N cards for prototype
	var player := turn_manager.game_state.players[local_player_id]
	var indices: Array[int] = []
	for i in range(mini(discard_count, player.hand.size())):
		indices.append(i)
	turn_manager.action_handler.effect_handler.resolve_hand_discard(indices)


func _on_zone_clicked(zone_number: int, _player_id: int) -> void:
	# For prototype: if we're in zone selection mode, use this zone
	_on_log_message("Zone %d clicked" % zone_number)


# --- Pointer interaction handlers ---

var _highlighted_slot: VRSlot3D = null
var _highlighted_card: VRCard3D = null


func _on_pointer_slot(slot: VRSlot3D) -> void:
	if _highlighted_slot and _highlighted_slot != slot:
		_highlighted_slot.set_highlighted(false)
	if _highlighted_card:
		_highlighted_card.animate_hover_return(environment.get_table_surface_y() + 0.001)
		_highlighted_card = null

	_highlighted_slot = slot
	slot.set_highlighted(true)


func _on_pointer_card(card: VRCard3D) -> void:
	if _highlighted_slot:
		_highlighted_slot.set_highlighted(false)
		_highlighted_slot = null
	if _highlighted_card and _highlighted_card != card:
		_highlighted_card.animate_hover_return(environment.get_table_surface_y() + 0.001)

	_highlighted_card = card
	card.animate_hover_lift(0.01)


func _on_pointer_nothing() -> void:
	if _highlighted_slot:
		_highlighted_slot.set_highlighted(false)
		_highlighted_slot = null
	if _highlighted_card:
		_highlighted_card.animate_hover_return(environment.get_table_surface_y() + 0.001)
		_highlighted_card = null
