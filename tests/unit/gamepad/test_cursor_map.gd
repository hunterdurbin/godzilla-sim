extends GdUnitTestSuite

## CursorMap — the directional navigation graph behind the controller
## cursor: history tiebreak (last 10 visited), transparent skip-through of
## invalid elements, hop cap, and the visited ring buffer.

const GRID := {
	"a": {"up": [], "right": ["b"], "down": ["hand"], "left": []},
	"b": {"up": [], "right": ["c"], "down": ["hand"], "left": ["a"]},
	"c": {"up": [], "right": [], "down": ["hand"], "left": ["b"]},
	"hand": {"up": ["a", "b", "c"], "right": [], "down": [], "left": []},
	"gap_start": {"up": [], "right": ["gap_mid"], "down": [], "left": []},
	"gap_mid": {"up": [], "right": ["gap_end"], "down": [], "left": ["gap_start"]},
	"gap_end": {"up": [], "right": [], "down": [], "left": ["gap_mid"]},
	"loop_a": {"up": [], "right": ["loop_b"], "down": [], "left": []},
	"loop_b": {"up": [], "right": ["loop_a"], "down": [], "left": []},
}


func _map() -> CursorMap:
	return CursorMap.new(GRID)


func test_plain_moves_and_dead_ends() -> void:
	var map := _map()
	assert_str(map.next("a", "right")).is_equal("b")
	assert_str(map.next("b", "left")).is_equal("a")
	assert_str(map.next("a", "left")).is_equal("")
	assert_str(map.next("a", "up")).is_equal("")
	assert_str(map.next("unknown", "right")).is_equal("")


func test_first_candidate_wins_without_history() -> void:
	assert_str(_map().next("hand", "up")).is_equal("a")


func test_history_tiebreak_returns_where_you_came_from() -> void:
	var map := _map()
	map.push_visited("b")
	map.push_visited("hand")
	assert_str(map.next("hand", "up")).is_equal("b")


func test_most_recent_history_wins_among_multiple_hits() -> void:
	var map := _map()
	map.push_visited("a")
	map.push_visited("c")
	assert_str(map.next("hand", "up")).is_equal("c")
	# Revisiting refreshes recency.
	map.push_visited("a")
	assert_str(map.next("hand", "up")).is_equal("a")


func test_invalid_elements_are_skipped_through() -> void:
	var map := _map()
	var only_end := func(id: String) -> bool: return id != "gap_mid"
	assert_str(map.next("gap_start", "right", only_end)).is_equal("gap_end")


func test_all_invalid_means_no_move() -> void:
	var map := _map()
	var nothing := func(_id: String) -> bool: return false
	assert_str(map.next("gap_start", "right", nothing)).is_equal("")


func test_cycle_of_invalid_elements_terminates() -> void:
	var map := _map()
	var nothing := func(_id: String) -> bool: return false
	assert_str(map.next("loop_a", "right", nothing)).is_equal("")


func test_unmapped_candidate_is_rejected() -> void:
	var map := CursorMap.new({"x": {"right": ["ghost"]}})
	assert_str(map.next("x", "right")).is_equal("")


func test_history_ring_caps_at_ten() -> void:
	var map := _map()
	for i in range(15):
		map.push_visited("id_%d" % i)
	var hist := map.visited()
	assert_int(hist.size()).is_equal(10)
	assert_str(hist[0]).is_equal("id_5")
	assert_str(hist[-1]).is_equal("id_14")


func test_set_map_swaps_edges_but_keeps_history() -> void:
	var map := _map()
	map.push_visited("b")
	map.push_visited("hand")
	map.set_map({
		"hand": {"up": ["a", "b"], "right": [], "down": [], "left": []},
		"a": {"up": [], "right": [], "down": [], "left": []},
		"b": {"up": [], "right": [], "down": [], "left": []},
	})
	# History survives the swap: up from the hand still returns to b.
	assert_str(map.next("hand", "up")).is_equal("b")
	# Old-map-only elements are gone.
	assert_str(map.next("gap_start", "right")).is_equal("")
