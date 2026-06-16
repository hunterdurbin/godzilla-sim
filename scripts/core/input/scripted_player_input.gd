class_name ScriptedPlayerInput
extends PlayerInput

## Test PlayerInput: answers come from pre-queued scripts, recorded in a call
## log for assertions. Every method resolves synchronously, so engine
## coroutines complete without frame waits.
##
## Usage:
##   var input := ScriptedPlayerInput.new()
##   input.answers = {"choose_option": [1], "select_zone": [3, 0]}
##   ... run the effect ...
##   assert(input.calls[0]["kind"] == "choose_option")
##
## When a queue is empty the base PlayerInput default applies (auto-pick
## first), so tests only script the decisions they care about.

## kind -> Array of queued answers, popped front-first.
var answers: Dictionary = {}

## Audit log: one {"kind": ..., "player_id": ..., args...} entry per decision.
var calls: Array[Dictionary] = []


func choose_option(player_id: int, options: Array[String], prompt: String) -> int:
	calls.append({"kind": "choose_option", "player_id": player_id, "options": options.duplicate(), "prompt": prompt})
	var queued: Variant = _next("choose_option")
	return int(queued) if queued != null else super(player_id, options, prompt)


func search_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, allow_skip: bool) -> Dictionary:
	calls.append({"kind": "search_cards", "player_id": player_id, "matching": matching.duplicate(), "prompt": prompt})
	var queued: Variant = _next("search_cards")
	return queued if queued != null else super(player_id, matching, all_cards, prompt, allow_skip)


func select_cards(player_id: int, matching: Array[Dictionary], all_cards: Array[Dictionary], prompt: String, min_count: int, max_count: int) -> Array[Dictionary]:
	calls.append({"kind": "select_cards", "player_id": player_id, "matching": matching.duplicate(), "prompt": prompt, "min": min_count, "max": max_count})
	var queued: Variant = _next("select_cards")
	if queued == null:
		return super(player_id, matching, all_cards, prompt, min_count, max_count)
	var typed: Array[Dictionary] = []
	for c in queued:
		typed.append(c)
	return typed


func choose_hand_discards(player_id: int, count: int, hand_size: int) -> Array[int]:
	calls.append({"kind": "choose_hand_discards", "player_id": player_id, "count": count, "hand_size": hand_size})
	var queued: Variant = _next("choose_hand_discards")
	if queued == null:
		return super(player_id, count, hand_size)
	var typed: Array[int] = []
	for v in queued:
		typed.append(int(v))
	return typed


func select_hand_card(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> int:
	calls.append({"kind": "select_hand_card", "player_id": player_id, "valid": valid_indices.duplicate(), "prompt": prompt})
	var queued: Variant = _next("select_hand_card")
	return int(queued) if queued != null else super(player_id, valid_indices, prompt, allow_skip)


func select_zone(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> int:
	calls.append({"kind": "select_zone", "player_id": player_id, "target": target_player_id, "valid": valid_zones.duplicate(), "prompt": prompt})
	var queued: Variant = _next("select_zone")
	return int(queued) if queued != null else super(player_id, target_player_id, valid_zones, prompt, allow_skip)


func select_strategy(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> int:
	calls.append({"kind": "select_strategy", "player_id": player_id, "target": target_player_id, "valid": valid_indices.duplicate(), "prompt": prompt})
	var queued: Variant = _next("select_strategy")
	return int(queued) if queued != null else super(player_id, target_player_id, valid_indices, prompt)


func arrange_deck(player_id: int, cards: Array[Dictionary], prompt: String) -> Dictionary:
	calls.append({"kind": "arrange_deck", "player_id": player_id, "cards": cards.duplicate(), "prompt": prompt})
	var queued: Variant = _next("arrange_deck")
	return queued if queued != null else super(player_id, cards, prompt)


func acknowledge_reveal(player_id: int, cards: Array[Dictionary], title: String) -> void:
	calls.append({"kind": "acknowledge_reveal", "player_id": player_id, "cards": cards.duplicate(), "title": title})


func choose_rankup(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String) -> int:
	calls.append({"kind": "choose_rankup", "player_id": player_id, "valid": valid_indices.duplicate(), "prompt": prompt})
	var queued: Variant = _next("choose_rankup")
	return int(queued) if queued != null else super(player_id, monsters, valid_indices, prompt)


func confirm_step(player_id: int, prompt: String, setting: String) -> void:
	calls.append({"kind": "confirm_step", "player_id": player_id, "prompt": prompt, "setting": setting})


## Count of recorded decisions of a given kind.
func count_calls(kind: String) -> int:
	var n: int = 0
	for c in calls:
		if c["kind"] == kind:
			n += 1
	return n


func _next(kind: String) -> Variant:
	var queue: Array = answers.get(kind, [])
	if queue.is_empty():
		return null
	return queue.pop_front()
