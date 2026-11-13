class_name ZoneSelectConstraints
extends RefCounted

## Optional extra rules for a multi-zone selection (`select_zones` /
## zones_target), carried as a plain Dictionary so it survives RPC as JSON:
##   "weights": {zone_index: int}  — cost of selecting each zone
##   "budget":  int                — selected weights may total at most this
##   "lowest_first": true          — picks must go in ascending weight order:
##                                    a zone is pickable only while no
##                                    unpicked zone in `weights` weighs less
##                                    (ties at the cutoff are the player's choice)
## An empty Dictionary means "no extra rules" (count/up_to only). Used by the
## rank-budget destroy ("any number whose ranks add up to N or less") and
## ESD05-005 ("in order from lowest rank, <Destroy> 3"). With lowest_first,
## `weights` must list EVERY candidate zone — unlisted zones never block.


static func rank_budget(weights: Dictionary, max_total: int) -> Dictionary:
	return {"weights": weights, "budget": max_total}


static func lowest_first(weights: Dictionary) -> Dictionary:
	return {"weights": weights, "lowest_first": true}


static func has_lowest_first(constraints: Dictionary) -> bool:
	return bool(constraints.get("lowest_first", false))


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
	## True if `zone` may join `selected` without breaking any rule.
	if has_budget(constraints) \
			and total(constraints, selected) + weight(constraints, zone) > budget(constraints):
		return false
	if has_lowest_first(constraints):
		var floor_weight: Variant = _lowest_unpicked_weight(constraints, selected)
		if floor_weight != null and weight(constraints, zone) > int(floor_weight):
			return false
	return true


static func is_valid(constraints: Dictionary, zones: Array) -> bool:
	## True if the whole selection honors every rule (host/engine-side check).
	if has_budget(constraints) and total(constraints, zones) > budget(constraints):
		return false
	if has_lowest_first(constraints) and not zones.is_empty():
		var floor_weight: Variant = _lowest_unpicked_weight(constraints, zones)
		if floor_weight != null:
			for z in zones:
				if weight(constraints, int(z)) > int(floor_weight):
					return false
	return true


static func prune(constraints: Dictionary, selected: Array) -> Array:
	## After a deselect: drop the heaviest picks until the selection is valid
	## again (lowest_first — unmarking a low card un-marks the higher ones that
	## depended on it). Returns the kept zones in their original order.
	var kept: Array = selected.duplicate()
	while not kept.is_empty() and not is_valid(constraints, kept):
		var heaviest: int = int(kept[0])
		for z in kept:
			if weight(constraints, int(z)) > weight(constraints, heaviest):
				heaviest = int(z)
		kept.erase(heaviest)
	return kept


static func _lowest_unpicked_weight(constraints: Dictionary, selected: Array) -> Variant:
	## Minimum weight among candidate zones not yet in `selected`; null when
	## every candidate is picked.
	var picked := {}
	for z in selected:
		picked[int(z)] = true
	var out: Variant = null
	for z in constraints.get("weights", {}):
		if picked.has(int(z)):
			continue
		var w: int = weight(constraints, int(z))
		if out == null or w < int(out):
			out = w
	return out


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
	if bool(parsed.get("lowest_first", false)):
		out["lowest_first"] = true
	return out
