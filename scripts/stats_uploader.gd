extends Node
## Autoload singleton: uploads game results to the API after online matches.

const API_BASE := "http://api.godzillatcg.com"
const ENDPOINT := "/game-results"


func upload_game_result(
	game_state: GameState,
	winner_id: int,
	reason: String,
	first_player_id: int,
	elapsed_times: Array[int],
	total_elapsed_ms: int,
	is_disconnect: bool,
) -> void:
	var payload := _build_payload(game_state, winner_id, reason, first_player_id, elapsed_times, total_elapsed_ms, is_disconnect)
	var json_str := JSON.stringify(payload)
	print("[StatsUploader] Uploading game result (%d bytes)..." % json_str.length())
	_post(json_str)


func _post(json_body: String, is_retry: bool = false) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var url := API_BASE + ENDPOINT
	var headers := ["Content-Type: application/json"]
	var err := http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		print("[StatsUploader] HTTP request error: %d" % err)
		http.queue_free()
		if not is_retry:
			print("[StatsUploader] Retrying once...")
			_post(json_body, true)
		return

	var result: Array = await http.request_completed
	http.queue_free()
	var http_result: int = result[0]
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	var body_str := body.get_string_from_utf8() if body.size() > 0 else "(empty)"

	if http_result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		print("[StatsUploader] Upload failed (result=%d, code=%d): %s" % [http_result, response_code, body_str])
		if not is_retry:
			print("[StatsUploader] Retrying once...")
			_post(json_body, true)
		return

	print("[StatsUploader] Upload successful (HTTP %d)" % response_code)


func _build_payload(
	game_state: GameState,
	winner_id: int,
	reason: String,
	first_player_id: int,
	elapsed_times: Array[int],
	total_elapsed_ms: int,
	is_disconnect: bool,
) -> Dictionary:
	var gm: String = NetworkManager.game_mode
	if gm.is_empty():
		gm = "rumble"

	var payload := {
		"game_version": NetworkManager.GAME_VERSION,
		"game_mode": gm,
		"is_public": NetworkManager.is_public_room,
		"winner": winner_id,
		"win_condition": _normalize_win_condition(reason, is_disconnect),
		"turn_count": game_state.turn_number,
		"starting_player": first_player_id,
		"is_disconnect": is_disconnect,
		"elapsed_time_ms": total_elapsed_ms,
		"reporter": "host" if NetworkManager.is_host() else "client",
		"players": [],
	}

	for i in range(2):
		var ps: PlayerState = game_state.players[i]
		payload["players"].append(_build_player_data(i, ps, game_state, elapsed_times))

	return payload


func _build_player_data(
	player_index: int,
	ps: PlayerState,
	game_state: GameState,
	elapsed_times: Array[int],
) -> Dictionary:
	# Build zone card stacks
	var zones_data: Array[Dictionary] = []
	for z in range(8):
		var cards: Array[String] = []
		for card in ps.zones[z]:
			cards.append(_get_card_number(card))
		zones_data.append({"zone": z + 1, "cards": cards})

	# Build strategy zone data
	var strategy_data: Array = []
	for s in range(ps.strategy_zones.size()):
		var sz: Dictionary = ps.strategy_zones[s]
		var card_num: Variant = null
		if not sz.is_empty():
			card_num = _get_card_number(sz)
		strategy_data.append({"index": s, "card": card_num})

	# Build discard pile card numbers
	var discard_ids: Array[String] = []
	for card in ps.discard_pile:
		discard_ids.append(_get_card_number(card))

	# Flat structure matching API/database column names
	return {
		"player_index": player_index,
		"player_name": game_state.player_names[player_index],
		"deck_name": DecklistManager.get_player_deck_name(player_index),
		"decklist_json": _get_decklist(player_index),
		"elapsed_time_ms": elapsed_times[player_index] if player_index < elapsed_times.size() else 0,
		"final_monster_zone": ps.monster_zone,
		"final_rage": ps.rage,
		"final_monster_id": _get_card_number(ps.current_monster) if not ps.current_monster.is_empty() else "",
		"final_deck_remaining": ps.main_deck.size(),
		"final_hand_size": ps.hand.size(),
		"final_discard_count": ps.discard_pile.size(),
		"final_discard_ids": discard_ids,
		"final_zones_json": zones_data,
		"final_strategy_zones_json": strategy_data,
	}


func _get_decklist(player_id: int) -> Dictionary:
	var deck_data = DecklistManager._player_decks[player_id]
	if deck_data == null:
		return {"monster": [], "main": []}
	return {
		"monster": _entries_from_monster_deck(deck_data["monster_deck"]),
		"main": deck_data["main_entries"],
	}


func _entries_from_monster_deck(monster_deck: Array) -> Array[Dictionary]:
	## Convert the built monster deck array back to entry format.
	var counts: Dictionary = {}
	var order: Array[String] = []
	for card in monster_deck:
		var cn: String = card.get("card_number", card.get("id", ""))
		if cn not in counts:
			counts[cn] = 0
			order.append(cn)
		counts[cn] += 1
	var entries: Array[Dictionary] = []
	for cn in order:
		entries.append({"quantity": counts[cn], "card_number": cn})
	return entries


static func _get_card_number(card: Dictionary) -> String:
	## Extract the base card number from a card dict. Instance IDs like
	## "EBP01-044_0_0" are stripped to "EBP01-044" via the CARD_TEMPLATES lookup.
	var instance_id: String = card.get("id", "")
	# Try direct template lookup — template "id" is the card number (e.g. "EBP01-044")
	if CardData.CARD_TEMPLATES.has(instance_id):
		return instance_id
	# Instance ID format: "CARD-NUM_deckId_copyIdx" — strip everything after the card number
	# Card numbers look like "EBP01-044", "ESD02-010", always LETTERS+DIGITS + "-" + DIGITS
	var parts := instance_id.split("_")
	if parts.size() > 1:
		return parts[0]
	return instance_id


static func _normalize_win_condition(reason: String, is_disconnect: bool) -> String:
	if is_disconnect:
		return "disconnect"
	if "invasion" in reason.to_lower():
		return "invasion"
	if "counter" in reason.to_lower():
		return "counter"
	if "concede" in reason.to_lower():
		return "concede"
	return reason
