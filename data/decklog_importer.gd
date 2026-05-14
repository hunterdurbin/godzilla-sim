class_name DecklogImporter extends Node
## Fetches Godzilla decks from Bushiroad's Deck Log site and normalizes them into
## the deckbuilder's entry format. Alt-art suffixes (`+`, `++`) are stripped so
## cards collapse onto the base IDs the sim knows.

signal completed(success: bool, payload: Dictionary, error_key: String)
# Success payload: {"title": String, "monster_entries": Array, "main_entries": Array, "game_title_id": int}
# Failure payload may carry {"game_title_id": int} for STR_DB_DECKLOG_ERR_WRONG_GAME_FMT.

const GAME_TITLE_ID_GODZILLA_EN := 7
const GAME_TITLE_ID_GODZILLA_JP := 13
const DEFAULT_HOST := "decklog-en.bushiroad.com"
const HOST_EN := "decklog-en.bushiroad.com"
const HOST_JP := "decklog.bushiroad.com"
const CODE_MAX_LENGTH := 10
const _CODE_RE := "^[A-Za-z0-9]+$"

const ERR_BAD_INPUT := "STR_DB_DECKLOG_ERR_BAD_INPUT"
const ERR_NETWORK := "STR_DB_DECKLOG_ERR_NETWORK"
const ERR_NOT_FOUND := "STR_DB_DECKLOG_ERR_NOT_FOUND"
const ERR_PARSE := "STR_DB_DECKLOG_ERR_PARSE"
const ERR_WRONG_GAME := "STR_DB_DECKLOG_ERR_WRONG_GAME_FMT"

var _http: HTTPRequest
var _in_flight: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


static func parse_input(raw: String, default_host: String = DEFAULT_HOST) -> Dictionary:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty():
		return {}

	var host := default_host
	var code := trimmed

	var lower := trimmed.to_lower()
	if lower.begins_with("http://") or lower.begins_with("https://"):
		var scheme_end := trimmed.find("://")
		var rest := trimmed.substr(scheme_end + 3)
		var slash := rest.find("/")
		if slash < 0:
			return {}
		var host_part := rest.substr(0, slash).to_lower()
		var path := rest.substr(slash)
		# strip query / fragment from path
		var q := path.find("?")
		if q >= 0:
			path = path.substr(0, q)
		var h := path.find("#")
		if h >= 0:
			path = path.substr(0, h)
		if not host_part.ends_with("bushiroad.com") or host_part.find("decklog") < 0:
			return {}
		var marker := "/view/"
		var idx := path.find(marker)
		if idx < 0:
			return {}
		code = path.substr(idx + marker.length()).strip_edges()
		code = code.trim_suffix("/")
		var sep := code.find("/")
		if sep >= 0:
			code = code.substr(0, sep)
		host = host_part

	if code.is_empty() or code.length() > CODE_MAX_LENGTH:
		return {}
	var regex := RegEx.new()
	regex.compile(_CODE_RE)
	if regex.search(code) == null:
		return {}

	return {"host": host, "code": code}


func fetch(raw_input: String, default_host: String = DEFAULT_HOST) -> int:
	if _in_flight:
		return ERR_BUSY
	var parsed := parse_input(raw_input, default_host)
	if parsed.is_empty():
		_emit_failure(ERR_BAD_INPUT, {})
		return ERR_INVALID_PARAMETER
	var host: String = parsed["host"]
	var code: String = parsed["code"]
	var url := "https://%s/system/app/api/view/%s" % [host, code]
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Referer: https://%s/view/%s" % [host, code],
	])
	_in_flight = true
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, "")
	if err != OK:
		_in_flight = false
		_emit_failure(ERR_NETWORK, {})
	return err


static func normalize_payload(parsed) -> Dictionary:
	# Decklog returns the literal `[]` (an empty Array) when the deck doesn't exist.
	if parsed == null or parsed is Array:
		return {}
	if not (parsed is Dictionary):
		return {}
	var game_id := int(parsed.get("game_title_id", -1))
	if game_id != GAME_TITLE_ID_GODZILLA_EN and game_id != GAME_TITLE_ID_GODZILLA_JP:
		return {"game_title_id": game_id}

	var monster_entries := _group_entries(parsed.get("p_list", []))
	var main_entries := _group_entries(parsed.get("list", []))
	return {
		"title": String(parsed.get("title", "")),
		"game_title_id": game_id,
		"monster_entries": monster_entries,
		"main_entries": main_entries,
	}


static func _group_entries(raw_list) -> Array:
	var result: Array = []
	if not (raw_list is Array):
		return result
	var index_by_base: Dictionary = {}
	for entry in raw_list:
		if not (entry is Dictionary):
			continue
		var raw_cn := String(entry.get("card_number", ""))
		if raw_cn.is_empty():
			continue
		var base := _normalize_card_number(raw_cn)
		if base.is_empty():
			continue
		var qty := int(entry.get("num", 1))
		if qty <= 0:
			continue
		if index_by_base.has(base):
			var i: int = index_by_base[base]
			result[i]["quantity"] = int(result[i]["quantity"]) + qty
		else:
			index_by_base[base] = result.size()
			result.append({"card_number": base, "quantity": qty})
	return result


static func _normalize_card_number(raw: String) -> String:
	# Strip alt-art suffixes (`+`, `++`, …) then prepend `E` if missing.
	# JA decklog returns "BP04-035" while the sim's CARD_TEMPLATES uses "EBP04-035".
	var base := raw
	while base.ends_with("+"):
		base = base.substr(0, base.length() - 1)
	if base.is_empty():
		return ""
	# Sim IDs always start with `E` followed by a set-code letter (e.g. EBP, ESD).
	# If the base already starts with `E` + uppercase letter, keep it. Otherwise prepend `E`.
	if base.length() >= 2 and base[0] == "E" and base[1] >= "A" and base[1] <= "Z":
		return base
	return "E" + base


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_emit_failure(ERR_NETWORK, {})
		return
	var text := body.get_string_from_utf8().strip_edges()
	if text.is_empty() or text == "[]":
		_emit_failure(ERR_NOT_FOUND, {})
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_emit_failure(ERR_PARSE, {})
		return
	var normalized := normalize_payload(json.data)
	if normalized.is_empty():
		_emit_failure(ERR_NOT_FOUND, {})
		return
	if not normalized.has("monster_entries"):
		# Wrong game — payload only carries {"game_title_id": id}
		_emit_failure(ERR_WRONG_GAME, normalized)
		return
	completed.emit(true, normalized, "")


func _emit_failure(error_key: String, payload: Dictionary) -> void:
	completed.emit(false, payload, error_key)
