class_name LogChat
extends Node

## Game log + chat concern for the game board. Owns the log token list, the
## broadcast buffer, rendering into the LogPanel, and chat dispatch/receive.
##
## Binds to TurnManager/EffectHandler log_message on
## GameSession.session_started (fires on initial start and every rematch;
## connects are idempotent). The board keeps thin shims (_on_log_message,
## _dispatch_chat, _rpc_receive_log, _rpc_receive_chat) for its many direct
## callers until the final slimming pass.

var _board: Node
var _session: GameSession

## Log entries are Dictionaries (tokens rendered by GameLog.render) or
## Strings (legacy/system messages that render as-is).
var log_tokens: Array = []
var pending_log_tokens: Array = [] # Buffered for next broadcast

var _log_output: RichTextLabel
var _chat_input: LineEdit
var _chat_char_count: Label


func _ready() -> void:
	_board = get_parent()
	var session_node := _board.get_node_or_null("GameSession")
	if session_node == null:
		push_error("[LogChat] No GameSession sibling — log signals will not bind.")
		return
	_session = session_node
	_session.session_started.connect(_bind_session)
	_log_output = _board.get_node_or_null("LogPanel/LogVBox/LogOutput")
	_chat_input = _board.get_node_or_null("LogPanel/LogVBox/ChatRow/ChatInput")
	_chat_char_count = _board.get_node_or_null("LogPanel/LogVBox/ChatRow/CharCount")
	if _chat_input:
		_chat_input.text_submitted.connect(_on_chat_submitted)
		_chat_input.text_changed.connect(_on_chat_text_changed)


func _bind_session() -> void:
	var tm: TurnManager = _session.turn_manager
	if tm == null:
		return # Client peer: log lines arrive via the state broadcast envelope
	_connect_once(tm.log_message, append_message)
	_connect_once(tm.action_handler.effect_handler.log_message, append_message)


func _connect_once(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


## Accepts a GameLog token Dictionary or a raw String (pre-formatted system
## messages like reconnect status). Tokens render in the local locale via
## GameLog.render; strings append as-is. On the multiplayer host the entry
## is also buffered for the next state broadcast.
func append_message(message) -> void:
	log_tokens.append(message)
	_render_to_output(render_entry(message))
	if _board.is_multiplayer_game and NetworkManager.is_host():
		pending_log_tokens.append(message)


## Append an entry received from the host (state-broadcast envelope) — same
## rendering, but never re-buffered for broadcast.
func append_remote_entry(entry) -> void:
	log_tokens.append(entry)
	_render_to_output(render_entry(entry))


func render_entry(entry) -> String:
	if typeof(entry) == TYPE_DICTIONARY:
		return GameLog.render(entry)
	return _board._resolve_translated_text(str(entry))


func clear() -> void:
	log_tokens.clear()
	if _log_output:
		_log_output.clear()


func _render_to_output(rendered: String) -> void:
	if _log_output:
		_log_output.append_text(rendered + "\n")
		_log_output.scroll_to_line(_log_output.get_line_count() - 1)


# --- Chat ---

func _on_chat_submitted(text: String) -> void:
	_chat_input.clear()
	_chat_input.release_focus()
	get_tree().create_timer(0.0).timeout.connect(_chat_input.grab_focus)
	_chat_char_count.text = str(_chat_input.max_length)
	dispatch_chat(text)


func _on_chat_text_changed(new_text: String) -> void:
	_chat_char_count.text = str(_chat_input.max_length - new_text.length())


## Filter, log, and broadcast a chat line. Shared by the desktop field and
## the mobile floating chat bar.
func dispatch_chat(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	var filtered := ChatFilter.filter(trimmed)
	var token := {"type": "chat", "sender_id": _board.local_player_id, "text": filtered}
	log_tokens.append(token)
	_render_to_output(GameLog.render(token))
	if _board.is_multiplayer_game:
		RpcLogger.log_send("receive_chat", 4 + filtered.length())
		_board._sync._rpc_receive_chat.rpc(_board.local_player_id, filtered)


# --- Remote receive (bodies for the MultiplayerSync forwarders) ---

## Host -> Client: log message (legacy raw-string path; kept for compatibility)
func receive_log(text: String) -> void:
	RpcLogger.log_receive("receive_log", text.length())
	log_tokens.append(text)
	_render_to_output(text)


## Any peer -> Any peer: chat message
func receive_chat(sender_player_id: int, text: String) -> void:
	RpcLogger.log_receive("receive_chat", 4 + text.length())
	if sender_player_id < 0 or sender_player_id > 1:
		return
	var filtered := ChatFilter.filter(text)
	var token := {"type": "chat", "sender_id": sender_player_id, "text": filtered}
	log_tokens.append(token)
	_render_to_output(GameLog.render(token))
	_board._notify_mobile_log_chat()
