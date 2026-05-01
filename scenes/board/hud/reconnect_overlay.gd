class_name ReconnectOverlay
extends ColorRect

## Drop-in disconnect/reconnect status banner. Listens for
## NetworkManager.player_disconnected / player_reconnected signals and
## presents either a claim-win countdown (host) or reconnecting message
## (client).
##
## Emits signals for the controller to act on:
##   claim_win_pressed   — host clicked "Claim Win" after timeout
##   return_to_menu_pressed — user gave up and wants to bail
##
## The actual reconnect attempt logic (NetworkManager.attempt_reconnect)
## lives in the controller — this component just handles the visual.

signal claim_win_pressed
signal return_to_menu_pressed

const RECONNECT_CLAIM_WIN_SECONDS: float = 10.0

@onready var _label: Label = $VBox/Label
@onready var _timer_label: Label = $VBox/TimerLabel
@onready var _claim_btn: Button = $VBox/ClaimBtn
@onready var _menu_btn: Button = $VBox/MenuBtn

var _waiting: bool = false
var _start_ms: int = 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_claim_btn.pressed.connect(func(): claim_win_pressed.emit())
	_menu_btn.pressed.connect(func(): return_to_menu_pressed.emit())
	if NetworkManager.has_signal("player_disconnected"):
		NetworkManager.player_disconnected.connect(_on_peer_disconnected)
	if NetworkManager.has_signal("player_reconnected"):
		NetworkManager.player_reconnected.connect(_on_peer_reconnected)


func _process(_delta: float) -> void:
	if not _waiting or not visible:
		return
	var elapsed_sec: float = (Time.get_ticks_msec() - _start_ms) / 1000.0
	if NetworkManager.is_host():
		var remaining := RECONNECT_CLAIM_WIN_SECONDS - elapsed_sec
		if remaining > 0:
			_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(ceili(remaining)))
		else:
			_timer_label.text = ""
			_claim_btn.visible = true
	else:
		_timer_label.text = tr("STR_GB_RECONNECTING_FMT").replace("{N}", str(int(elapsed_sec)))


func _on_peer_disconnected(_peer_id: int) -> void:
	# Only show for online modes — LAN games handle disconnect by
	# ending the match outright (controller decides).
	var is_online := NetworkManager.mode in [
		NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT
	]
	if not is_online:
		return
	_waiting = true
	_start_ms = Time.get_ticks_msec()
	if NetworkManager.is_host():
		_label.text = tr("STR_GB_OPPONENT_DISCONNECTED_WAIT")
		_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(int(RECONNECT_CLAIM_WIN_SECONDS)))
		_claim_btn.visible = false
	else:
		_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
		_timer_label.text = ""
		_claim_btn.visible = false
	_menu_btn.visible = true
	visible = true


func _on_peer_reconnected(_peer_id: int) -> void:
	_waiting = false
	visible = false


## Public hide hook for the controller (e.g. game ended by other means).
func hide_overlay() -> void:
	_waiting = false
	visible = false
