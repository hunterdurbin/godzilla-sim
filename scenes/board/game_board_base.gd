extends Control

## GameBoardBase — drop-in starting point for a new GameBoard scene.
##
## Pre-wired with GameSession + MultiplayerSync + EffectUIRouter +
## DefaultOverlayPack. Handles the bootstrap (mode branching, host/solo
## start, bot setup, signal wiring) so subclasses only need to focus on
## visuals.
##
## Two ways to use:
##
## A) **Inherit from this scene** (Godot scene inheritance) — your scene
##    gets the same tree + script. Override the protected hooks below
##    (`_on_phase_started`, `_on_turn_started`, `_on_log_message`,
##    `_on_game_ended`, etc.) to update your visual layout. Drop your
##    layout into `BoardLayoutSlot`.
##
## B) **Instance this scene** as a child of your own root and call
##    `start()` from your script. Subscribe to the same signals on
##    `session.turn_manager` from your own _ready().
##
## Cross-scene multiplayer contract: root node MUST be named "GameBoard"
## so the MultiplayerSync NodePath matches between peers loading
## different .tscn files. See docs/new_game_board.md.

@onready var session: GameSession = $GameSession
@onready var multiplayer_sync: MultiplayerSync = $GameSession/MultiplayerSync
@onready var effect_ui_router: EffectUIRouter = $GameSession/EffectUIRouter
@onready var overlay_pack: Control = $DefaultOverlayPack
@onready var board_layout_slot: Control = $BoardLayoutSlot

var local_player_id: int = 0
var is_bot_game: bool = false
var is_multiplayer_game: bool = false

# View-board flow state (set when a deck-search/card-select/deck-arrange
# overlay's "View Board" button is pressed; restored when player taps the
# host scene's "Show Cards" button — host scene wires a button to call
# `dismiss_view_board()`).
var _view_board_source: Control = null


func _ready() -> void:
	is_multiplayer_game = NetworkManager.is_multiplayer()
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	local_player_id = NetworkManager.get_local_player_id() if is_multiplayer_game \
		else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)

	if is_multiplayer_game and not NetworkManager.is_host():
		# Client: wait for host RPCs to populate state. Subclasses that need
		# client-side bootstrap can override _on_client_ready().
		_on_client_ready()
		return

	# Host / solo
	session.start_host_session(CardData, local_player_id)

	if is_bot_game:
		session.setup_bot(local_player_id)

	_wire_effect_router()
	_connect_session_signals()
	_on_host_ready()

	# Auto-pick first player so the loop doesn't stall on coin flip in solo
	# mode. Subclasses can override _on_host_ready() to delay or customize.
	if not is_multiplayer_game:
		session.start_game(0)


## Override to set custom visual updates.
func _on_phase_started(_phase: CardEnums.GamePhase) -> void: pass
func _on_phase_ended(_phase: CardEnums.GamePhase) -> void: pass
func _on_turn_started(_player_id: int) -> void: pass
func _on_awaiting_action(_valid_actions: Array) -> void: pass
func _on_game_ended(_winner_id: int, _reason_key: String) -> void: pass
func _on_log_message(_token) -> void: pass
func _on_confirmation_requested(_prompt: String, setting: String) -> void:
	# Default: auto-confirm anything. Subclasses override to show a UI.
	session.confirm()


## Override for client-side bootstrap (e.g. show a "waiting for host" panel).
func _on_client_ready() -> void: pass


## Override for any extra host-side setup (e.g. wire your action buttons,
## connect to player_state signals, etc.). Called after session is started
## and signals connected.
func _on_host_ready() -> void: pass


## When an overlay's "View Board" button is pressed, the overlay calls this
## (via router.on_view_board_request). Default behavior: stash the overlay
## reference. Subclasses typically override to also show a "Show Cards"
## button that, when pressed, calls `dismiss_view_board()`.
func _on_view_board_request(overlay: Control) -> void:
	_view_board_source = overlay


## Re-show the stashed overlay (called when player taps "Show Cards").
func dismiss_view_board() -> void:
	if _view_board_source and is_instance_valid(_view_board_source):
		if _view_board_source.has_method("reshow"):
			_view_board_source.reshow()
		else:
			_view_board_source.visible = true
	_view_board_source = null


## Translate a prompt string (defaults to GameSettings/TranslationServer
## via tr() with whitespace preservation). Subclasses can override.
func _resolve_translated_text(text: String) -> String:
	if not text.begins_with("STR_"):
		return text
	var stripped := text.strip_edges()
	var translated := tr(stripped)
	if translated == stripped:
		return text
	return text.replace(stripped, translated)


# --- Internal wiring ---

func _wire_effect_router() -> void:
	effect_ui_router.translate_prompt = _resolve_translated_text
	effect_ui_router.on_view_board_request = _on_view_board_request
	# card_zoom_request is auto-set by CardZoomOverlay's self-registration
	# when DefaultOverlayPack is present. Subclasses can override.
	effect_ui_router.bind(session, multiplayer_sync, local_player_id)


func _connect_session_signals() -> void:
	var tm := session.turn_manager
	tm.phase_started.connect(_on_phase_started)
	tm.phase_ended.connect(_on_phase_ended)
	tm.turn_started.connect(_on_turn_started)
	tm.awaiting_player_action.connect(_on_awaiting_action)
	tm.game_ended.connect(_on_game_ended)
	tm.log_message.connect(_on_log_message)
	tm.confirmation_requested.connect(_on_confirmation_requested)
	# Effect handler log messages also go to _on_log_message so subclasses
	# get a unified stream.
	session.effect_handler.log_message.connect(_on_log_message)
