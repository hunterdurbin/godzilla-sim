class_name FirstPlayerUI
extends Node

## First-player (coin flip) choice concern: the go-first/go-second prompt,
## the waiting state on the non-choosing side, the starter-monster preview,
## and the four RPC bodies that carry the flow across peers.
##
## The game-start orchestration stays in game_board._start_game(): it calls
## start_choice()/start_waiting(), awaits `result >= 0`, then finish().

var _board: Node

var choosing: bool = false
var chooser_id: int = -1 # Player who gets to decide
var result: int = -1 # Resolved first player id (-1 = pending)


func _ready() -> void:
	_board = get_parent()


## Reset pending state and show the go-first/go-second buttons (local chooser).
func start_choice(p_chooser_id: int) -> void:
	chooser_id = p_chooser_id
	result = -1
	choosing = true
	_show_choice()


## Reset pending state and show the waiting prompt (remote player chooses).
func start_waiting() -> void:
	result = -1
	choosing = true
	_show_waiting()


## Tear down the choice UI after the result resolved.
func finish() -> void:
	choosing = false
	_cleanup_ui()


func _show_waiting() -> void:
	_board._disable_all_buttons()
	_board.btn_concede.disabled = true
	_board._set_action_buttons_visible(false)
	_board.card_select_prompt.text = tr("STR_GB_COIN_FLIP_WAITING")
	_board.action_prompt_panel.visible = true
	_show_local_starter_monster()


func _show_choice() -> void:
	_board._disable_all_buttons()
	_board.btn_concede.disabled = true
	_board._set_action_buttons_visible(false)
	_board.card_select_prompt.text = tr("STR_GB_COIN_FLIP_WON")
	_board.action_prompt_panel.visible = true
	_show_local_starter_monster()

	var container := VBoxContainer.new()
	container.name = "FirstPlayerContainer"
	if _board._is_mobile_layout:
		container.anchor_left = 0.3
		container.anchor_right = 0.7
		container.anchor_top = 1.0
		container.anchor_bottom = 1.0
		container.offset_top = -90.0
		container.offset_bottom = -4.0
		container.z_index = 55
		_board.add_child(container)
	else:
		_board.action_panel.add_child(container)

	var btn_first := Button.new()
	btn_first.text = tr("STR_GB_GO_FIRST")
	btn_first.custom_minimum_size.x = 325
	btn_first.size_flags_horizontal = Control.SIZE_SHRINK_END if not _board._is_mobile_layout else Control.SIZE_EXPAND_FILL
	btn_first.pressed.connect(_on_chosen.bind(true))
	container.add_child(btn_first)

	var btn_second := Button.new()
	btn_second.text = tr("STR_GB_GO_SECOND")
	btn_second.custom_minimum_size.x = 325
	btn_second.size_flags_horizontal = Control.SIZE_SHRINK_END if not _board._is_mobile_layout else Control.SIZE_EXPAND_FILL
	btn_second.pressed.connect(_on_chosen.bind(false))
	container.add_child(btn_second)

	GamepadHelper.register_modal(container, func() -> Control: return btn_first)


## Render only the local player's rank 1 monster into its starting zone so the
## player has visual context during the first/second choice. Does NOT sync hands,
## decks, or any other game state — those become visible once the game starts.
func _show_local_starter_monster() -> void:
	var monster_deck: Array = DecklistManager.get_player_monster_deck(_board.local_player_id)
	var rank1: Dictionary = {}
	for m in monster_deck:
		if m.get("rank", 0) == 1:
			rank1 = m
			break
	if rank1.is_empty():
		return
	var local_board: Control = _board.player1_board if _board.local_player_id == 0 else _board.player2_board
	if not local_board:
		return
	if local_board.has_method("apply_monster_gradient"):
		local_board.apply_monster_gradient(rank1)
	var temp_state := PlayerState.new(_board.local_player_id)
	temp_state.current_monster = rank1
	temp_state.monster_zone = int(rank1.get("start_zone", 1))
	if local_board.has_method("_sync_monster"):
		local_board._sync_monster(temp_state, 0, 0)


func _cleanup_ui() -> void:
	var container: Node = _board.action_panel.get_node_or_null("FirstPlayerContainer")
	if not container:
		container = _board.get_node_or_null("FirstPlayerContainer")
	if container:
		container.queue_free()
	_board.action_prompt_panel.visible = false
	_board._set_action_buttons_visible(true)
	_board.btn_concede.disabled = false


func _on_chosen(go_first: bool) -> void:
	if not choosing:
		return
	_cleanup_ui()

	var chosen_id: int = chooser_id if go_first else (1 - chooser_id)

	if _board.is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("first_player_choice_resolved", 4)
		_board._sync._rpc_first_player_choice_resolved.rpc_id(NetworkManager.host_peer_id, chosen_id)
	else:
		result = chosen_id


# --- RPC bodies (MultiplayerSync forwards here via the board shims) ---

## Host -> Client: tell the client to wait while the host chooses
func rpc_waiting() -> void:
	RpcLogger.log_receive("first_player_waiting", 0)
	if NetworkManager.is_host():
		return
	choosing = true
	_show_waiting()


## Host -> Client: ask the client to choose first/second
func rpc_choice_requested() -> void:
	RpcLogger.log_receive("first_player_choice_requested", 0)
	if NetworkManager.is_host():
		return
	choosing = true
	chooser_id = _board.local_player_id
	_show_choice()


## Client -> Host: resolve the first-player choice
func rpc_choice_resolved(chosen_id: int) -> void:
	RpcLogger.log_receive("first_player_choice_resolved", 4)
	if not NetworkManager.is_host():
		return
	result = chosen_id


## Host -> Client: tell waiting client to restore action panel after coin flip
func rpc_cleanup() -> void:
	RpcLogger.log_receive("cleanup_first_player", 0)
	if NetworkManager.is_host():
		return
	choosing = false
	_cleanup_ui()
