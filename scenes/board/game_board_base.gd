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
@onready var board_layout_slot: Control = $BoardLayoutSlot

## Wiring slots — set these in the inspector for explicit composition.
## When unset, the base resolves them via tree-walk in `_ready` so legacy
## scenes keep working. Drag a node from the scene tree into each slot
## to make the wiring visible in the editor.
@export_group("Wiring (optional — falls back to tree-walk if unset)")
@export var overlay_pack: Control
@export var local_seat: SeatContainer
@export var opponent_seat: SeatContainer
## Any node that emits `action_pressed(action: CardEnums.ActionType)`.
## When unset, the base scans descendants for the signal.
@export var action_panel: Node
@export_group("")

var local_player_id: int = 0
var is_bot_game: bool = false
var is_multiplayer_game: bool = false

# View-board flow state (set when a deck-search/card-select/deck-arrange
# overlay's "View Board" button is pressed; restored when player taps the
# host scene's "Show Cards" button — host scene wires a button to call
# `dismiss_view_board()`).
var _view_board_source: Control = null

# Built lazily during _on_host_ready when an ActionPanel descendant is
# present in the scene. Designer can replace by setting `selection_controller`
# in their subclass before the base's _on_host_ready runs.
var selection_controller: SelectionModeController = null


func _ready() -> void:
	is_multiplayer_game = NetworkManager.is_multiplayer()
	is_bot_game = NetworkManager.mode == NetworkManager.Mode.SOLO_BOT
	local_player_id = NetworkManager.get_local_player_id() if is_multiplayer_game \
		else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)

	_resolve_wiring_slots()

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
	_wire_player_boards()
	_wire_action_panel()
	_on_host_ready()

	# Auto-pick first player so the loop doesn't stall on coin flip in solo
	# mode. Subclasses can override _on_host_ready() to delay or customize.
	if not is_multiplayer_game:
		session.start_game(0)


func _process(_delta: float) -> void:
	# Drive per-frame snap-preview animation while a hand card is dragged.
	# Cheap when no drag is active (early-out).
	if selection_controller:
		selection_controller.update_snap_preview()


## Override to set custom visual updates.
func _on_phase_started(_phase: CardEnums.GamePhase) -> void: pass
func _on_phase_ended(_phase: CardEnums.GamePhase) -> void: pass
func _on_turn_started(_player_id: int) -> void: pass
func _on_awaiting_action(_valid_actions: Array) -> void: pass
func _on_game_ended(_winner_id: int, _reason_key: String) -> void: pass
func _on_log_message(_token) -> void: pass
func _on_confirmation_requested(prompt: String, setting: String) -> void:
	# Settings-gated auto-confirm. If GameSettings.X is on, fire the
	# host's confirm() immediately. Otherwise prompt the local player
	# via the action panel (when one is wired) and confirm only if
	# they press Confirm. Spectator and AI-only scenes fall through to
	# auto-confirm since they have no UI to ask.
	var auto_on: bool = false
	if setting != "" and setting in GameSettings:
		auto_on = bool(GameSettings.get(setting))
	if auto_on:
		session.confirm()
		return
	if selection_controller and _action_panel_visible_for_local_turn():
		selection_controller.prompt_confirmation(prompt, session.confirm)
		return
	# No UI available — keep the engine moving.
	session.confirm()


func _action_panel_visible_for_local_turn() -> bool:
	# Only prompt the local seated player. Bot's turn or spectator: skip.
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
		if session.current_player_id() != local_player_id:
			return false
	if NetworkManager.is_spectator():
		return false
	return true


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

## Resolve the optional `@export Node` wiring slots from the scene tree
## when the inspector hasn't populated them. Keeps legacy scenes working
## while letting new scenes opt into explicit wiring.
func _resolve_wiring_slots() -> void:
	if overlay_pack == null:
		overlay_pack = get_node_or_null("DefaultOverlayPack") as Control
	if local_seat == null or opponent_seat == null:
		var seats := _find_descendants_of_class("SeatContainer")
		for s in seats:
			match s.role:
				SeatContainer.Role.LOCAL:
					if local_seat == null: local_seat = s
				SeatContainer.Role.OPPONENT:
					if opponent_seat == null: opponent_seat = s
				SeatContainer.Role.PLAYER_0:
					if local_seat == null: local_seat = s
				SeatContainer.Role.PLAYER_1:
					if opponent_seat == null: opponent_seat = s
	if action_panel == null:
		action_panel = _find_first_descendant_with_signal("action_pressed")


## Builds a SelectionModeController over the configured action_panel if
## one is present. Designer who wants custom behavior can override
## `selection_controller` before _on_host_ready runs.
func _wire_action_panel() -> void:
	if selection_controller != null:
		return  # subclass already provided one
	if action_panel == null:
		return  # no ActionPanel in tree — designer drives actions another way
	selection_controller = SelectionModeController.new(session, action_panel, self)
	selection_controller.bind()


func _find_first_descendant_with_signal(signal_name: String) -> Node:
	var queue: Array[Node] = [self]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node != self and node.has_signal(signal_name):
			return node
		for child in node.get_children():
			queue.append(child)
	return null


## Find every PlayerBoard descendant in the scene tree and wire its
## snapshot_provider so it can self-refresh from session state. Designers
## who want different behavior can disable a board's `auto_bind` in the
## inspector or override this method.
func _wire_player_boards() -> void:
	for board in _find_descendants_of_class("PlayerBoard"):
		if board.auto_bind and not board.snapshot_provider.is_valid():
			board.snapshot_provider = _player_snapshot


## Default snapshot provider. Works for both host (reads
## session.effect_handler live) and client (reads session.client_* cache
## populated by RPC) modes. Designer subclasses can override for custom
## modifier sources or to add hand_rank_mods etc.
func _player_snapshot(pid: int) -> Dictionary:
	if session.is_running() and session.game_state:
		var eh := session.effect_handler
		var zone_cp: Array = eh.get_zone_cp_modifiers(pid) if eh else []
		var strat_cp: Array = eh.get_strategy_cp_modifiers(pid) if eh else []
		var monster_cp: int = eh.get_monster_cp_modifier(pid) if eh else 0
		var cp_mod: int = monster_cp
		for v in zone_cp: cp_mod += v
		for v in strat_cp: cp_mod += v
		return {
			"state": session.game_state.players[pid],
			"cp_mod": cp_mod,
			"threat_mod": eh.get_threat_level_modifier(pid) if eh else 0,
			"zone_cp_mods": zone_cp,
			"strategy_cp_mods": strat_cp,
			"zone_rank_mods": eh.get_zone_rank_modifiers(pid) if eh else [],
			"monster_cp_mod": monster_cp,
			"hand_rank_mods": [],
		}
	# Client mode: read from broadcast cache.
	if pid < session.client_players.size() and session.client_players[pid]:
		return {
			"state": session.client_players[pid],
			"cp_mod": session.client_cp_modifiers[pid] if pid < session.client_cp_modifiers.size() else 0,
			"threat_mod": session.client_threat_modifiers[pid] if pid < session.client_threat_modifiers.size() else 0,
			"zone_cp_mods": session.client_zone_cp_mods[pid] if pid < session.client_zone_cp_mods.size() else [],
			"strategy_cp_mods": session.client_strategy_cp_mods[pid] if pid < session.client_strategy_cp_mods.size() else [],
			"zone_rank_mods": session.client_zone_rank_mods[pid] if pid < session.client_zone_rank_mods.size() else [],
			"monster_cp_mod": session.client_monster_cp_mods[pid] if pid < session.client_monster_cp_mods.size() else 0,
			"hand_rank_mods": session.client_hand_rank_mods[pid] if pid < session.client_hand_rank_mods.size() else [],
		}
	return {}


func _find_descendants_of_class(class_name_str: String) -> Array:
	var out: Array = []
	_walk_for_class(self, class_name_str, out)
	return out


func _walk_for_class(node: Node, class_name_str: String, out: Array) -> void:
	for child in node.get_children():
		if child.get_class() == class_name_str or (child.get_script() != null and str(child.get_script().get_global_name()) == class_name_str):
			out.append(child)
		_walk_for_class(child, class_name_str, out)


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
