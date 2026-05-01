extends "res://scenes/board/game_board_base.gd"

## GameBoardTemplate — pre-populated drop-in starter scene.
##
## Inherits everything from game_board_base.gd. Adds only one piece of
## scene-specific wiring: the Return-to-Menu button at the top.
##
## A designer who inherits GameBoardTemplate.tscn gets a working board
## with both seats populated, HUD, action panel, and log. They reskin
## visuals and ship — no engine wiring needed.

@onready var menu_button: Button = $TopBar/MenuButton
@onready var end_game_panel: PanelContainer = $EndGamePanel
@onready var first_player_overlay: FirstPlayerOverlay = $FirstPlayerOverlay
@onready var reconnect_overlay: ReconnectOverlay = $ReconnectOverlay


func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)
	end_game_panel.menu_pressed.connect(_on_menu_pressed)
	end_game_panel.rematch_pressed.connect(_on_rematch_pressed)
	first_player_overlay.choice_made.connect(_on_first_player_chosen)
	reconnect_overlay.return_to_menu_pressed.connect(_on_menu_pressed)
	reconnect_overlay.claim_win_pressed.connect(_on_claim_win_pressed)
	# Bot mode: disable the base's auto-start so the player can choose
	# who goes first via FirstPlayerOverlay. Solo (no bot) still autostarts.
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
		auto_start_first_player = false
	super()
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT and session and session.is_running():
		first_player_overlay.show_choice(0)


func _on_first_player_chosen(chosen_player_id: int) -> void:
	if session and session.is_running() and not session.turn_manager.is_game_over:
		# turn_manager.start_game has already been called in solo paths,
		# but here we held off via auto_start_first_player = false.
		session.start_game(chosen_player_id)


func _on_claim_win_pressed() -> void:
	# Host claim-win after disconnect timeout. The legacy game_board.gd
	# wires this to a stats upload + final disconnect handler. Designers
	# extending the template can override this hook for richer behavior.
	if session and session.is_running():
		session.end_game(NetworkManager.local_player_id, "STR_LOG_WIN_REASON_DISCONNECT")
	reconnect_overlay.hide_overlay()


func _on_menu_pressed() -> void:
	NetworkManager.is_in_game = false
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _on_rematch_pressed() -> void:
	# Minimal rematch path: reload the same scene. Full host/client
	# rematch synchronization (the legacy game_board.gd flow) is out
	# of scope for the template — designers can override this hook.
	NetworkManager.change_scene(scene_file_path)
