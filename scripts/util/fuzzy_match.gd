class_name FuzzyMatch
extends RefCounted
## VSCode-flavored fuzzy match scoring.
##
## Returns -1 if needle is not a subsequence of haystack (case-insensitive).
## Otherwise returns a positive score: base 10 per matched char, +20 at a
## word boundary, +15 for consecutive runs, +5 for case-exact matches.
## Empty needle returns 0 (matches everything, neutral score).

static func score(needle: String, haystack: String) -> int:
	if needle.is_empty():
		return 0
	if haystack.is_empty():
		return -1
	var n_lower := needle.to_lower()
	var h_lower := haystack.to_lower()
	var s := 0
	var h_idx := 0
	var prev_match := -2
	for n_idx in range(n_lower.length()):
		var ch := n_lower[n_idx]
		var found := -1
		for j in range(h_idx, h_lower.length()):
			if h_lower[j] == ch:
				found = j
				break
		if found == -1:
			return -1
		s += 10
		if found == 0 or h_lower[found - 1] in [" ", "-", "_", "/", "."]:
			s += 20
		if found == prev_match + 1:
			s += 15
		if haystack[found] == needle[n_idx]:
			s += 5
		prev_match = found
		h_idx = found + 1
	return s
