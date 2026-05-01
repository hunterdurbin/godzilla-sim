class_name HandSlot
extends CardManager

## Self-binding hand component. Drop into a SeatContainer next to a
## PlayerBoard — auto-attaches itself as the board's `hand_manager`,
## anchors to the seat's bottom (LOCAL) or top (OPPONENT) edge, and
## resizes to the seat's width. Card spawning / removal is handled
## by `PlayerBoard.sync_to_state` (which runs whenever PlayerState's
## hand_changed signal fires); this script only handles wiring +
## positioning so the designer doesn't have to touch the GameBoard
## controller.
##
## Usage:
##   GameBoard
##   └── BoardLayoutSlot
##       └── LocalSeat / OpponentSeat
##           ├── PlayerBoard          (auto_bind = true)
##           └── HandSlot              ← drop me here

@export_group("Auto-bind")
## When true, attaches itself to the seat's PlayerBoard as its
## hand_manager and positions relative to the seat's edge.
@export var auto_bind: bool = true

@export_group("Positioning")
## Auto: LOCAL seat → bottom edge, OPPONENT seat → top edge.
## Override when your variant wants a non-standard placement.
@export_enum("Auto", "Bottom", "Top") var anchor_edge: int = 0
## Hand's max width as a fraction of the seat's width.
@export_range(0.1, 1.0, 0.05) var width_pct: float = 0.95

var _bound_seat: SeatContainer = null


func _ready() -> void:
	super()
	if not auto_bind:
		return
	_bound_seat = BoardModule.find_seat(self)
	if _bound_seat == null:
		push_warning("[HandSlot] No SeatContainer ancestor — drop me inside a seat.")
		return
	if not _bound_seat.role_changed.is_connected(_on_role_changed):
		_bound_seat.role_changed.connect(_on_role_changed)
	if not _bound_seat.resized.is_connected(_position_to_seat):
		_bound_seat.resized.connect(_position_to_seat)
	# Defer one frame so the seat's PlayerBoard auto-instantiation has run
	# AND the GameSession has had its chance to fire session_started.
	call_deferred("_attach_and_position")


func _on_role_changed(_new_pid: int) -> void:
	_attach_and_position()


func _attach_and_position() -> void:
	if _bound_seat == null:
		return
	# Find the seat's PlayerBoard, attach as its hand_manager, force a
	# re-sync so existing cards appear (PlayerBoard's first sync_to_state
	# would have run with hand_manager == null and skipped card spawning).
	var pbs := _bound_seat.find_children("*", "PlayerBoard", true, false)
	if not pbs.is_empty():
		var pb: PlayerBoard = pbs[0]
		pb.hand_manager = self
		var session := BoardModule.find_session(self)
		if session:
			var ps: PlayerState = null
			if session.is_running():
				ps = session.get_player(pb.player_id)
			elif pb.player_id < session.client_players.size():
				ps = session.client_players[pb.player_id]
			if ps:
				pb.sync_to_state(ps)
		# Wire drag-to-zone via the GameBoard's SelectionModeController
		# (set up by GameBoardBase). Belt-and-suspenders: bind() also
		# defers a _wire_hand_managers() pass, but calling here too keeps
		# the wiring correct if HandSlot attaches after bind() ran.
		var board_root := find_parent("GameBoard")
		if board_root and "selection_controller" in board_root:
			var ctrl = board_root.selection_controller
			if ctrl and ctrl.has_method("wire_hand_manager"):
				ctrl.wire_hand_manager(pb)
	_position_to_seat()


func _position_to_seat() -> void:
	if _bound_seat == null:
		return
	var rect := _bound_seat.get_global_rect()
	if rect.size == Vector2.ZERO:
		# Seat hasn't been laid out yet — try again next frame.
		call_deferred("_position_to_seat")
		return
	var edge := anchor_edge
	if edge == 0:
		edge = 2 if _bound_seat.role == SeatContainer.Role.OPPONENT else 1
	var anchor_y: float
	if edge == 2:  # top
		anchor_y = rect.position.y
	else:  # bottom
		anchor_y = rect.position.y + rect.size.y
	global_position = Vector2(rect.position.x + rect.size.x / 2.0, anchor_y)
	max_width = rect.size.x * width_pct
	arrange_cards(false)
