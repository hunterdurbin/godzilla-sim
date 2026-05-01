extends Button

## Drop-in save-game button. Auto-binds to the GameSession, captures the
## first-player id from `turn_manager.turn_started`, and writes a save
## file via GameSerializer when pressed. Designer-friendly: just drop
## anywhere in the GameBoard tree, no wiring needed.

@export var auto_bind: bool = true

var _session: GameSession = null
var _first_player_id: int = 0


func _ready() -> void:
	text = tr("STR_GB_SAVE_GAME")
	pressed.connect(_on_pressed)
	if auto_bind:
		_try_bind()


func _try_bind() -> void:
	_session = BoardModule.find_session(self)
	if _session == null:
		return
	if _session.is_running():
		_bind()
	else:
		_session.session_started.connect(_bind, CONNECT_ONE_SHOT)


func _bind() -> void:
	if _session == null or _session.turn_manager == null:
		return
	if not _session.turn_manager.turn_started.is_connected(_on_turn_started):
		_session.turn_manager.turn_started.connect(_on_turn_started)


func _on_turn_started(player_id: int) -> void:
	# First turn_started fires with the player who goes first.
	if _session and _session.game_state and _session.game_state.turn_number == 1:
		_first_player_id = player_id


func _on_pressed() -> void:
	if _session == null or not _session.is_running() or _session.game_state == null:
		return
	SfxManager.play("ui_click")
	var mode_str: String
	match NetworkManager.mode:
		NetworkManager.Mode.SOLO: mode_str = "solo"
		NetworkManager.Mode.SOLO_BOT: mode_str = "solo_bot"
		_: mode_str = "solo"
	var diff_str: String = ""
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
		diff_str = BotConfig.Difficulty.keys()[NetworkManager.bot_difficulty]
	var deck_names: Array[String] = [
		DecklistManager.get_player_deck_name(0),
		DecklistManager.get_player_deck_name(1),
	]
	# Capture a fresh seed from the RNG so a load from this save replays
	# deterministically (the original seed is stale — RNG has advanced).
	var save_seed := randi()
	var data := GameSerializer.serialize_game_state(
		_session.game_state, _first_player_id, mode_str, diff_str, deck_names, save_seed
	)
	var path := GameSerializer.save_game_to_file(data)
	if not path.is_empty():
		text = tr("STR_GB_SAVED")
		disabled = true
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(self):
				text = tr("STR_GB_SAVE_GAME")
				disabled = false
		)
