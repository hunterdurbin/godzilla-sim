extends HBoxContainer

## Drop-in chat input row. Submits a chat token to the GameBoard's
## LogPanel (via append_log) and, in multiplayer, broadcasts via
## MultiplayerSync._rpc_receive_chat. Self-binds — designer drops it
## inside the LogPanel (or anywhere in the GameBoard tree) and it Just
## Works.
##
## Filtered through ChatFilter for profanity etc.

@export var max_length: int = 200

@onready var _input: LineEdit = $Input
@onready var _count: Label = $CharCount

var _log_panel: PanelContainer = null
var _multiplayer_sync: Node = null


func _ready() -> void:
	_input.max_length = max_length
	_input.placeholder_text = tr("STR_GB_CHAT_PLACEHOLDER")
	_count.text = str(max_length)
	_input.text_submitted.connect(_on_submitted)
	_input.text_changed.connect(_on_text_changed)
	# Defer so LogPanel + MultiplayerSync are ready in the tree.
	call_deferred("_resolve_targets")


func _resolve_targets() -> void:
	var board := find_parent("GameBoard")
	if board:
		var panels := board.find_children("*", "LogPanel", true, false)
		# LogPanel doesn't have a class_name; fallback by node-name lookup.
		if panels.is_empty():
			var lp := board.find_child("LogPanel", true, false)
			if lp:
				_log_panel = lp
		else:
			_log_panel = panels[0]
	_multiplayer_sync = BoardModule.find_multiplayer_sync(self)


func _on_submitted(text: String) -> void:
	_input.clear()
	_input.release_focus()
	get_tree().create_timer(0.0).timeout.connect(_input.grab_focus)
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	var filtered := ChatFilter.filter(trimmed)
	var sender_id: int = NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
	var token := {"type": "chat", "sender_id": sender_id, "text": filtered}
	if _log_panel and _log_panel.has_method("append_log"):
		_log_panel.append_log(token)
	if NetworkManager.is_multiplayer() and _multiplayer_sync and _multiplayer_sync.has_method("_rpc_receive_chat"):
		RpcLogger.log_send("receive_chat", 4 + filtered.length())
		_multiplayer_sync._rpc_receive_chat.rpc(sender_id, filtered)
	_count.text = str(max_length)


func _on_text_changed(new_text: String) -> void:
	_count.text = str(max_length - new_text.length())
