extends Button

## Drop-in hand-sort button. Walks up to its enclosing SeatContainer to
## resolve which player's hand to sort, finds the seat's PlayerBoard,
## and sorts its hand_manager using `GameSettings.hand_sort_type_order`
## and `GameSettings.hand_sort_rank_ascending`.
##
## Place this button inside a SeatContainer next to the corresponding
## PlayerBoard. Without a seat ancestor it falls back to the explicit
## `player_id` export (defaults to 0 = local).

@export var player_id: int = 0

const _TYPE_ORDERS: Array = [
	[0, 1, 2], # Monster, Battle, Strategy
	[0, 2, 1], # Monster, Strategy, Battle
	[1, 0, 2], # Battle, Monster, Strategy
	[1, 2, 0], # Battle, Strategy, Monster
	[2, 0, 1], # Strategy, Monster, Battle
	[2, 1, 0], # Strategy, Battle, Monster
]


func _ready() -> void:
	pressed.connect(_on_pressed)
	var seat := BoardModule.find_seat(self)
	if seat:
		player_id = seat.get_player_id()
		if not seat.role_changed.is_connected(_on_seat_role_changed):
			seat.role_changed.connect(_on_seat_role_changed)


func _on_seat_role_changed(new_player_id: int) -> void:
	player_id = new_player_id


func _on_pressed() -> void:
	var pb := _find_player_board()
	if pb == null or pb.hand_manager == null:
		return
	var hand_mgr := pb.hand_manager
	if hand_mgr.managed_cards.size() <= 1:
		return

	var order: Array = _TYPE_ORDERS[clampi(GameSettings.hand_sort_type_order, 0, 5)]
	var type_priority := {}
	for i in range(order.size()):
		type_priority[order[i]] = i
	var rank_asc: bool = GameSettings.hand_sort_rank_ascending

	hand_mgr.managed_cards.sort_custom(func(a: Control, b: Control) -> bool:
		var ad: Dictionary = a.card_data if "card_data" in a else {}
		var bd: Dictionary = b.card_data if "card_data" in b else {}
		var pa: int = type_priority.get(int(ad.get("card_type", 0)), 0)
		var pb_idx: int = type_priority.get(int(bd.get("card_type", 0)), 0)
		if pa != pb_idx:
			return pa < pb_idx
		var ra: int = int(ad.get("rank", 0))
		var rb: int = int(bd.get("rank", 0))
		if ra != rb:
			return (ra < rb) if rank_asc else (ra > rb)
		return ad.get("id", "") < bd.get("id", "")
	)
	hand_mgr.arrange_cards(true)


func _find_player_board() -> Node:
	# Walk up to the seat container, search its descendants for PlayerBoard;
	# if no seat, search the GameBoard root.
	var root: Node = BoardModule.find_seat(self)
	if root == null:
		root = self.find_parent("GameBoard")
	if root == null:
		return null
	return _find_in(root, "PlayerBoard")


func _find_in(node: Node, class_name_str: String) -> Node:
	if node.get_script() and str(node.get_script().get_global_name()) == class_name_str:
		return node
	for child in node.get_children():
		var found := _find_in(child, class_name_str)
		if found:
			return found
	return null
