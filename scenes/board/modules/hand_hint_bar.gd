class_name HandHintBar
extends Node
## Gamepad hint cluster for the hovered hand card (presentation-only module).
##
## While the cursor free-browses the hand on the local player's own turn (no
## prompt, confirmation or pending action), the bottom-left HandHintCluster
## panel lists the pad actions the hovered card can actually take: A = play
## (dispatched by card type), LT = rage, RT = invade. Rows the card can't use
## stay hidden; the whole panel hides in pointer mode, on mobile and whenever
## SelectionController reports no legal action — which also keeps it from
## ever overlapping ActionPrompt in the same corner (prompts imply a
## selection mode, and selection modes blank the hints).
##
## Never loaded by the harness stub or headless server board — no RPC-surface
## impact.

var _board: Node
var _cluster: Control
var _row_play: Control
var _row_rage: Control
var _row_invade: Control


func _ready() -> void:
	_board = get_parent()
	_cluster = _board.get_node("HandHintCluster")
	_row_play = _cluster.get_node("VBox/RowPlay")
	_row_rage = _cluster.get_node("VBox/RowRage")
	_row_invade = _cluster.get_node("VBox/RowInvade")
	_board.get_node("GamepadBoardNav").nav_state_changed.connect(_refresh)
	_board.get_node("SelectionController").action_buttons_changed.connect(_refresh)
	# A device flip can wake the cursor on an unchanged element without a
	# nav_state_changed, and the labels/panel don't self-hide the way
	# ControllerGlyph does — listen to the device signals directly.
	GamepadHelper.gamepad_detected.connect(_refresh)
	GamepadHelper.pointer_detected.connect(_refresh)


func _refresh() -> void:
	if _board._is_mobile_layout or not GamepadHelper.is_using_gamepad():
		_cluster.visible = false
		return
	var nav: GamepadBoardNav = _board.get_node("GamepadBoardNav")
	var card: Control = nav.browse_hovered_hand_card()
	var actions: Array[int] = []
	if card:
		actions = _board._selection.hand_card_hint_actions(card)
	_row_play.visible = actions.has(CardEnums.ActionType.PLAY_MONSTER) \
			or actions.has(CardEnums.ActionType.PLAY_BATTLE) \
			or actions.has(CardEnums.ActionType.PLAY_STRATEGY)
	_row_rage.visible = actions.has(CardEnums.ActionType.GAIN_RAGE)
	_row_invade.visible = actions.has(CardEnums.ActionType.INVADE)
	_cluster.visible = not actions.is_empty()


## Pure decision core (unit-tested): which actions a hovered card earns.
## [param lists] holds logical-hand-index arrays keyed "battle"/"strategy"/
## "monster"/"rage"/"invade"; [param enabled] maps ActionType -> whether the
## matching action button is enabled (the "awaiting main-phase action"
## proxy). Returns the legal ActionTypes for the card at [param logical_idx].
static func compute_hint_actions(card_type: int, logical_idx: int,
		lists: Dictionary, enabled: Dictionary) -> Array[int]:
	var actions: Array[int] = []
	if logical_idx < 0:
		return actions
	var play_action := -1
	var play_list := ""
	match card_type:
		CardEnums.CardType.MONSTER:
			play_action = CardEnums.ActionType.PLAY_MONSTER
			play_list = "monster"
		CardEnums.CardType.BATTLE:
			play_action = CardEnums.ActionType.PLAY_BATTLE
			play_list = "battle"
		CardEnums.CardType.STRATEGY:
			play_action = CardEnums.ActionType.PLAY_STRATEGY
			play_list = "strategy"
	if play_action >= 0 and _hintable(play_action, play_list, logical_idx, lists, enabled):
		actions.append(play_action)
	if _hintable(CardEnums.ActionType.GAIN_RAGE, "rage", logical_idx, lists, enabled):
		actions.append(CardEnums.ActionType.GAIN_RAGE)
	if _hintable(CardEnums.ActionType.INVADE, "invade", logical_idx, lists, enabled):
		actions.append(CardEnums.ActionType.INVADE)
	return actions


static func _hintable(action: int, list_key: String, logical_idx: int,
		lists: Dictionary, enabled: Dictionary) -> bool:
	if not enabled.get(action, false):
		return false
	var list: Array = lists.get(list_key, [])
	return logical_idx in list
