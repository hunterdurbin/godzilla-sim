class_name ZoneSelectConstraints
extends RefCounted

## Optional extra rules for a multi-zone selection (`select_zones` /
## zones_target), carried as a plain Dictionary so it survives RPC as JSON:
##   "weights": {zone_index: int}  — cost of selecting each zone
##   "budget":  int                — selected weights may total at most this
## An empty Dictionary means "no extra rules" (count/up_to only). Used by the
## rank-budget destroy ("any number whose ranks add up to N or less").


static func rank_budget(weights: Dictionary, max_total: int) -> Dictionary:
	return {"weights": weights, "budget": max_total}


static func has_budget(constraints: Dictionary) -> bool:
	return constraints.has("budget")


static func budget(constraints: Dictionary) -> int:
	return int(constraints.get("budget", 0))


static func weight(constraints: Dictionary, zone: int) -> int:
	return int(constraints.get("weights", {}).get(zone, 0))


static func total(constraints: Dictionary, zones: Array) -> int:
	var sum: int = 0
	for z in zones:
		sum += weight(constraints, int(z))
	return sum


static func can_add(constraints: Dictionary, selected: Array, zone: int) -> bool:
	## True if `zone` may join `selected` without breaking the budget.
	if not has_budget(constraints):
		return true
	return total(constraints, selected) + weight(constraints, zone) <= budget(constraints)


static func is_valid(constraints: Dictionary, zones: Array) -> bool:
	if not has_budget(constraints):
		return true
	return total(constraints, zones) <= budget(constraints)


static func to_json(constraints: Dictionary) -> String:
	return "" if constraints.is_empty() else JSON.stringify(constraints)


static func from_json(json: String) -> Dictionary:
	## Inverse of to_json — JSON turns int keys into strings and ints into
	## floats, so normalize both back.
	if json.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return {}
	var out: Dictionary = {}
	if parsed.has("weights"):
		var weights: Dictionary = {}
		for k in parsed["weights"]:
			weights[int(k)] = int(parsed["weights"][k])
		out["weights"] = weights
	if parsed.has("budget"):
		out["budget"] = int(parsed["budget"])
	return out
