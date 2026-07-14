class_name CursorMap
extends RefCounted
## Generic directional navigation graph for the controller cursor.
##
## A map is a Dictionary of element id -> {"up": [ids], "right": [ids],
## "down": [ids], "left": [ids]} — an explicit, hand-editable statement of
## where the cursor travels from each element (BoardNavGraph.build() in
## scenes/board/modules/board_nav_graph.gd produces the game-board map;
## menu/UI maps plug into the same class). set_map() swaps the edges while
## keeping the visited history, so dynamic rebuilds don't lose the
## "return where you came from" behavior.
##
## Direction lists may hold multiple candidates. Resolution:
##   1. the candidate visited most recently (last HISTORY_MAX elements)
##      wins the tiebreak — "up from the hand returns to wherever you came
##      from";
##   2. otherwise list order;
##   3. candidates rejected by the is_valid callback (hidden slot, element
##      outside a prompt's valid set) are traversed THROUGH: their own list
##      for the same direction continues the search (bounded, cycle-guarded),
##      so an invalid element is transparent rather than a wall.

const HISTORY_MAX := 10
const MAX_HOPS := 8

var _map: Dictionary = {}
## Most recent LAST; unique entries (revisiting moves the id to the back).
var _visited: Array[String] = []


func _init(map: Dictionary) -> void:
	_map = map


## Swap the adjacency map in place, KEEPING the visited history — dynamic
## rebuilds (hand size changed, prompt opened) must not amnesia the
## "return where you came from" tie-break.
func set_map(map: Dictionary) -> void:
	_map = map


func has_element(id: String) -> bool:
	return _map.has(id)


func push_visited(id: String) -> void:
	_visited.erase(id)
	_visited.append(id)
	while _visited.size() > HISTORY_MAX:
		_visited.remove_at(0)


func visited() -> Array[String]:
	return _visited.duplicate()


func clear_history() -> void:
	_visited.clear()


## The element the cursor should move to from `from_id` in `dir`
## ("up"/"right"/"down"/"left"), or "" for no move. is_valid(id) -> bool
## filters candidates; pass Callable() to accept every mapped element.
func next(from_id: String, dir: String, is_valid: Callable = Callable()) -> String:
	var seen := {from_id: true}
	var frontier: Array[String] = _candidates(from_id, dir)
	var hops := 0
	while not frontier.is_empty() and hops < MAX_HOPS:
		hops += 1
		var pick := _pick(frontier)
		if pick == "":
			return ""
		if _accepts(pick, is_valid):
			return pick
		# Transparent skip: continue the search through the invalid element,
		# same direction, never revisiting.
		seen[pick] = true
		frontier.erase(pick)
		for follow_up in _candidates(pick, dir):
			if not seen.has(follow_up) and follow_up not in frontier:
				frontier.append(follow_up)
	return ""


func _candidates(id: String, dir: String) -> Array[String]:
	var entry: Dictionary = _map.get(id, {})
	var out: Array[String] = []
	out.assign(entry.get(dir, []))
	return out


## Most recently visited candidate wins; unvisited candidates rank by list
## order after all visited ones lose to the freshest.
func _pick(candidates: Array[String]) -> String:
	if candidates.is_empty():
		return ""
	var best := candidates[0]
	var best_rank := -1
	for candidate in candidates:
		var rank := _visited.rfind(candidate)
		if rank > best_rank:
			best_rank = rank
			best = candidate
	return best


func _accepts(id: String, is_valid: Callable) -> bool:
	if not _map.has(id):
		return false
	if not is_valid.is_valid():
		return true
	return bool(is_valid.call(id))
