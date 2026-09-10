class_name CardSearch
extends RefCounted

## The deck builder's card-search grammar as a reusable static utility
## (used by the F4 board editor pool; the deck builder keeps its own copy
## because its fuzzy trait matching is printing/game-mode aware).
##
## Grammar: comma-separated criteria, ANDed. Each criterion is either a
## numeric compare `[field][op][int]` (op ∈ >=, <=, !=, ==, =, >, <; field
## aliases below; no field = any numeric field) or a fuzzy substring match
## over name / id / description / traits / common_names. A leading `!`
## negates the criterion.

const _FIELD_ALIASES := {
	"c": "cp", "cp": "cp", "counter": "cp", "power": "cp", "counterpower": "cp",
	"t": "threat", "threat": "threat", "level": "threat", "threatlevel": "threat",
	"r": "rank", "rank": "rank",
}

const _NUMERIC_FIELDS := ["cp", "threat", "rank"]


static func parse(raw: String) -> Array:
	var criteria: Array = []
	for chunk in raw.split(","):
		var token: String = chunk.strip_edges().to_lower()
		if token.is_empty():
			continue
		var negate: bool = token.begins_with("!")
		if negate:
			token = token.substr(1).strip_edges()
			if token.is_empty():
				continue
		var compare := _try_parse_compare(token)
		var entry: Dictionary
		if not compare.is_empty():
			entry = compare
		else:
			entry = {"type": "fuzzy", "needle": token}
		entry["negate"] = negate
		criteria.append(entry)
	return criteria


static func matches(card: Dictionary, criteria: Array) -> bool:
	for criterion in criteria:
		var matched: bool = _evaluate(card, criterion)
		if criterion.get("negate", false):
			matched = not matched
		if not matched:
			return false
	return true


static func _try_parse_compare(token: String) -> Dictionary:
	var ops := [">=", "<=", "!=", "==", "=", ">", "<"]
	var op_str := ""
	var op_pos := -1
	for op in ops:
		var p := token.find(op)
		if p >= 0:
			op_str = op
			op_pos = p
			break
	if op_pos < 0:
		return {}
	var lhs := token.substr(0, op_pos).strip_edges().replace(" ", "").replace("_", "")
	var rhs := token.substr(op_pos + op_str.length()).strip_edges()
	if not rhs.is_valid_int():
		return {}
	var field := "any"
	if not lhs.is_empty():
		if not _FIELD_ALIASES.has(lhs):
			return {}
		field = _FIELD_ALIASES[lhs]
	if op_str == "==":
		op_str = "="
	return {"type": "compare", "field": field, "op": op_str, "value": rhs.to_int()}


static func _evaluate(card: Dictionary, criterion: Dictionary) -> bool:
	match str(criterion.get("type", "")):
		"compare":
			var field: String = criterion.get("field", "any")
			var op: String = criterion.get("op", "=")
			var value: int = criterion.get("value", 0)
			if field == "any":
				for f: String in _NUMERIC_FIELDS:
					if _card_has_field(card, f) and _compare_int(_card_field(card, f), op, value):
						return true
				return false
			if not _card_has_field(card, field):
				return false
			return _compare_int(_card_field(card, field), op, value)
		"fuzzy":
			return _matches_fuzzy(card, criterion.get("needle", ""))
	return false


static func _card_has_field(card: Dictionary, field: String) -> bool:
	match field:
		"cp": return card.has("counter_power")
		"threat": return card.has("threat_level")
		"rank": return card.has("rank")
	return false


static func _card_field(card: Dictionary, field: String) -> int:
	match field:
		"cp": return card.get("counter_power", 0)
		"threat": return card.get("threat_level", 0)
		"rank": return card.get("rank", 0)
	return 0


static func _compare_int(lhs: int, op: String, rhs: int) -> bool:
	match op:
		">": return lhs > rhs
		"<": return lhs < rhs
		">=": return lhs >= rhs
		"<=": return lhs <= rhs
		"=": return lhs == rhs
		"!=": return lhs != rhs
	return false


static func _matches_fuzzy(card: Dictionary, needle: String) -> bool:
	if str(card.get("name", "")).to_lower().contains(needle):
		return true
	if str(card.get("id", "")).to_lower().contains(needle):
		return true
	if str(card.get("description", "")).to_lower().contains(needle):
		return true
	for t in card.get("traits", []):
		if CardEnums.trait_to_string(t).to_lower().contains(needle):
			return true
	for cn in card.get("common_names", []):
		if String(cn).to_lower().contains(needle):
			return true
	return false
