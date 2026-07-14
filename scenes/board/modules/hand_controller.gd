class_name HandController
extends Node

## Hand presentation concern: expand/collapse toggles for the local and
## opponent hands, hand sorting, and the temporary collapse/restore used
## while dragging or picking cards.
##
## IMPORTANT: tweens always animate the existing hand Node2Ds in place —
## the hands are never reparented (reparenting while a hover tween runs
## corrupts positions; see project gotchas).

const HAND_EXPAND_OFFSET: float = 160.0
const OPPONENT_HAND_EXPAND_OFFSET: float = 195.0

const HAND_SORT_TYPE_ORDERS: Array = [
	[0, 1, 2], # Monster, Battle, Strategy
	[0, 2, 1], # Monster, Strategy, Battle
	[1, 0, 2], # Battle, Monster, Strategy
	[1, 2, 0], # Battle, Strategy, Monster
	[2, 0, 1], # Strategy, Monster, Battle
	[2, 1, 0], # Strategy, Battle, Monster
]

var _board: Node

var hand_expanded: bool = false
var opponent_hand_expanded: bool = false
var _hand_tween: Tween = null
var _opponent_hand_tween: Tween = null


func _ready() -> void:
	_board = get_parent()


## Wire the four hand buttons. Called from the board's _ready.
func setup() -> void:
	_board.hand_toggle_button.pressed.connect(_on_hand_toggle_pressed)
	_board.sort_hand_button.pressed.connect(_on_sort_hand_pressed)
	_board.opponent_hand_toggle_button.pressed.connect(_on_opponent_hand_toggle_pressed)
	_board.opponent_sort_hand_button.pressed.connect(_on_opponent_sort_hand_pressed)


func _local_hand() -> Node2D:
	return _board.player1_hand if _board.local_player_id == 0 else _board.player2_hand


func _local_space() -> Control:
	return _board.player1_hand_space if _board.local_player_id == 0 else _board.player2_hand_space


func _opponent_hand() -> Node2D:
	return _board.player1_hand if _board.local_player_id == 1 else _board.player2_hand


func _opponent_space() -> Control:
	return _board.player1_hand_space if _board.local_player_id == 1 else _board.player2_hand_space


func _on_hand_toggle_pressed() -> void:
	set_hand_expanded(not hand_expanded)


## Programmatic expand/collapse (controller hand browsing uses this too).
func set_hand_expanded(expanded: bool) -> void:
	hand_expanded = expanded
	_board.hand_toggle_button.text = "▼" if hand_expanded else "▲"

	var local_hand := _local_hand()
	var local_space := _local_space()
	if not local_space or not local_hand:
		return

	var rect := local_space.get_global_rect()
	var expand_offset: float = 120.0 if _board._is_mobile_layout else HAND_EXPAND_OFFSET
	var y_offset := -expand_offset if hand_expanded else 0.0
	var target_y := rect.position.y + rect.size.y / 2.0 + y_offset

	_tween_hand_to(local_hand, target_y)


func _on_opponent_hand_toggle_pressed() -> void:
	opponent_hand_expanded = not opponent_hand_expanded
	_board.opponent_hand_toggle_button.text = "▲" if opponent_hand_expanded else "▼"

	var opp_hand := _opponent_hand()
	var opp_space := _opponent_space()
	if not opp_space or not opp_hand:
		return

	var rect := opp_space.get_global_rect()
	var base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
	var target_y := base_y + (OPPONENT_HAND_EXPAND_OFFSET if opponent_hand_expanded else 0.0)
	_tween_opponent_hand_to(opp_hand, target_y)


func _on_sort_hand_pressed() -> void:
	sort_player_hand(_board.local_player_id)


func _on_opponent_sort_hand_pressed() -> void:
	sort_player_hand(1 - _board.local_player_id)


func sort_player_hand(player_id: int) -> void:
	var hand_mgr: CardManager = _board.player1_hand if player_id == 0 else _board.player2_hand
	if not hand_mgr or hand_mgr.managed_cards.size() <= 1:
		return

	var order: Array = HAND_SORT_TYPE_ORDERS[clampi(GameSettings.hand_sort_type_order, 0, 5)]
	var type_priority := {}
	for i in range(order.size()):
		type_priority[order[i]] = i

	var rank_asc: bool = GameSettings.hand_sort_rank_ascending

	hand_mgr.managed_cards.sort_custom(func(a: Control, b: Control) -> bool:
		var ad: Dictionary = a.card_data if "card_data" in a else {}
		var bd: Dictionary = b.card_data if "card_data" in b else {}
		var pa: int = type_priority.get(int(ad.get("card_type", 0)), 0)
		var pb: int = type_priority.get(int(bd.get("card_type", 0)), 0)
		if pa != pb:
			return pa < pb
		var ra: int = int(ad.get("rank", 0))
		var rb: int = int(bd.get("rank", 0))
		if ra != rb:
			return (ra < rb) if rank_asc else (ra > rb)
		return ad.get("id", "") < bd.get("id", "")
	)

	hand_mgr.arrange_cards(true)


func temporarily_collapse_hand() -> void:
	if not hand_expanded:
		return
	var local_hand := _local_hand()
	var local_space := _local_space()
	if not local_space or not local_hand:
		return
	var rect := local_space.get_global_rect()
	_tween_hand_to(local_hand, rect.position.y + rect.size.y / 2.0)


func restore_expanded_hand() -> void:
	if not hand_expanded:
		return
	var local_hand := _local_hand()
	var local_space := _local_space()
	if not local_space or not local_hand:
		return
	var rect := local_space.get_global_rect()
	var expand_offset: float = 120.0 if _board._is_mobile_layout else HAND_EXPAND_OFFSET
	_tween_hand_to(local_hand, rect.position.y + rect.size.y / 2.0 - expand_offset)


func temporarily_collapse_opponent_hand() -> void:
	if not opponent_hand_expanded or _board.is_multiplayer_game:
		return
	var opp_hand := _opponent_hand()
	var opp_space := _opponent_space()
	if not opp_space or not opp_hand:
		return
	var rect := opp_space.get_global_rect()
	var base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
	_tween_opponent_hand_to(opp_hand, base_y)


func restore_expanded_opponent_hand() -> void:
	if not opponent_hand_expanded or _board.is_multiplayer_game:
		return
	var opp_hand := _opponent_hand()
	var opp_space := _opponent_space()
	if not opp_space or not opp_hand:
		return
	var rect := opp_space.get_global_rect()
	var base_y := rect.position.y - OPPONENT_HAND_EXPAND_OFFSET
	_tween_opponent_hand_to(opp_hand, base_y + OPPONENT_HAND_EXPAND_OFFSET)


func _tween_hand_to(hand: Node2D, target_y: float) -> void:
	if _hand_tween and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand_tween = create_tween()
	_hand_tween.set_ease(Tween.EASE_OUT)
	_hand_tween.set_trans(Tween.TRANS_CUBIC)
	_hand_tween.tween_property(hand, "global_position:y", target_y, 0.2)


func _tween_opponent_hand_to(hand: Node2D, target_y: float) -> void:
	if _opponent_hand_tween and _opponent_hand_tween.is_valid():
		_opponent_hand_tween.kill()
	_opponent_hand_tween = create_tween()
	_opponent_hand_tween.set_ease(Tween.EASE_OUT)
	_opponent_hand_tween.set_trans(Tween.TRANS_CUBIC)
	_opponent_hand_tween.tween_property(hand, "global_position:y", target_y, 0.2)
