extends Control

## Stub presentation scene + designer template for a new GameBoard.
##
## Required scene-tree contract — any GameBoard scene that wants the full
## logic + multiplayer + effect-prompt routing must include these named
## children at the same NodePath on host and client:
##   - GameSession             (Node + game_session.gd)
##     - MultiplayerSync       (Node + multiplayer_sync.gd)
##     - EffectUIRouter        (Node + effect_ui_router.gd)
##
## Optional scene children (registered with the EffectUIRouter):
##   - DiscardViewOverlay, MonsterDeckViewOverlay, ZoneStackViewOverlay,
##     CardZoomOverlay, DeckSearchOverlay, DeckArrangeOverlay,
##     CardSelectOverlay
##   - Plus a ChoiceOverlay controller instance (no .tscn — see choice_overlay.gd)
##
## Designer wiring summary (the bare minimum to get a running game):
##   1. session.start_host_session(CardData, local_player_id)
##   2. session.setup_bot(local_player_id) if is_bot_game
##   3. session.start_game(first_player_id)
##   4. effect_ui_router.bind(session, multiplayer_sync, local_player_id)
##      after registering your overlay-show handlers.
##   5. Connect to session.turn_manager signals for phase/turn/log updates.

@onready var session: GameSession = $GameSession
@onready var multiplayer_sync: MultiplayerSync = $GameSession/MultiplayerSync
@onready var effect_ui_router: EffectUIRouter = $GameSession/EffectUIRouter

@onready var status_turn: Label = $StatusBox/TurnLabel
@onready var status_player: Label = $StatusBox/PlayerLabel
@onready var status_phase: Label = $StatusBox/PhaseLabel
@onready var status_log: RichTextLabel = $StatusBox/Log
@onready var btn_end: Button = $StatusBox/EndMainButton
@onready var btn_menu: Button = $StatusBox/MenuButton

var local_player_id: int = 0
var is_bot_game: bool = false


func _ready() -> void:
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	local_player_id = NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0
	print("[NewGameBoard] _ready: mode=%s local_pid=%d is_bot=%s" % [
		NetworkManager.Mode.keys()[NetworkManager.mode], local_player_id, is_bot_game])

	btn_end.pressed.connect(_on_end_main_pressed)
	btn_menu.pressed.connect(_on_menu_pressed)
	btn_end.disabled = true

	if NetworkManager.is_host() or not NetworkManager.is_multiplayer():
		_start_host_or_solo()
	else:
		_log("Client mode — waiting for host state. (Stub does not yet receive RPCs.)")


func _start_host_or_solo() -> void:
	session.start_host_session(CardData, local_player_id)

	# Wire game-loop signals (these are TurnManager signals — GameSession
	# does not yet re-emit them; bind directly to session.turn_manager).
	var tm := session.turn_manager
	tm.phase_started.connect(_on_phase_started)
	tm.turn_started.connect(_on_turn_started)
	tm.awaiting_player_action.connect(_on_awaiting_action)
	tm.game_ended.connect(_on_game_ended)
	tm.log_message.connect(_on_log_message)
	tm.confirmation_requested.connect(_on_confirmation_requested)

	if is_bot_game:
		session.setup_bot(local_player_id)

	# A real GameBoard scene would register overlay handlers here:
	#   effect_ui_router.register_handler("deck_search", _show_my_deck_search)
	#   effect_ui_router.register_handler("card_select", _show_my_card_select)
	#   ... etc.
	# Then call effect_ui_router.bind(session, multiplayer_sync, local_player_id).
	# This stub skips overlay registration — effect prompts will silently
	# auto-resolve or warn in the log.

	session.start_game(0)
	_log("Game started (host/solo).")
	print("[NewGameBoard] start_game(0) returned")


func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	status_phase.text = "Phase: %s" % CardEnums.GamePhase.keys()[phase]


func _on_turn_started(player_id: int) -> void:
	status_turn.text = "Turn: %d" % session.game_state.turn_number
	status_player.text = "Active: %s" % GameLog.player_name(player_id)


func _on_awaiting_action(_valid_actions: Array) -> void:
	var local_turn := session.current_player_id() == local_player_id
	btn_end.disabled = not local_turn or is_bot_game


func _on_game_ended(winner_id: int, reason_key: String) -> void:
	btn_end.disabled = true
	_log("[color=yellow]Game over.[/color] Winner: %s (%s)" % [GameLog.player_name(winner_id), reason_key])


func _on_log_message(token) -> void:
	if token is Dictionary:
		_log(GameLog.render(token))
	else:
		_log(str(token))


func _on_confirmation_requested(_prompt: String, _setting: String) -> void:
	# Stub auto-confirms anything (no prompt UI yet).
	session.confirm()


func _on_end_main_pressed() -> void:
	session.submit_action(CardEnums.ActionType.PASS, {})


func _on_menu_pressed() -> void:
	NetworkManager.is_in_game = false
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _log(msg: String) -> void:
	status_log.append_text(msg + "\n")
	status_log.scroll_to_line(status_log.get_line_count() - 1)
