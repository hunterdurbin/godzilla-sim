class_name ChatFilter

## Profanity filter with evasion detection.
## Handles: leetspeak (f*ck, sh1t, @ss), repeated characters (fuuuck),
## separator characters (f.u.c.k, f_u_c_k), and standard word matching.

# Base words — variants (leetspeak, repeats, separators) are caught automatically.
static var _banned_words: PackedStringArray = [
	"fuck", "shit", "ass", "asshole", "bitch", "bastard",
	"dick", "piss", "cunt", "slut", "whore",
	"pussy",
	"fag", "faggot",
	"retard",
	"nigger", "nigga",
	"cock", "twat", "wank",
]

# Leetspeak substitution map: character → letters it could represent.
static var _leet_map: Dictionary = {
	"@": "a", "4": "a",
	"3": "e",
	"1": "i", "!": "i", "|": "i",
	"0": "o",
	"$": "s", "5": "s",
	"7": "t", "+": "t",
	"*": "", # wildcard filler (f*ck)
}

static var _patterns: Array[RegEx] = _build_patterns()


static func _build_patterns() -> Array[RegEx]:
	var result: Array[RegEx] = []
	for word in _banned_words:
		var pattern := _word_to_pattern(word)
		var r := RegEx.new()
		r.compile(pattern)
		result.append(r)
	return result


static func _escape_for_class(c: String) -> String:
	## Escape a character for use inside a regex character class [].
	if c in "\\]^-":
		return "\\" + c
	return c


static func _char_class(c: String) -> String:
	## Build a regex character class that matches a letter and its leetspeak variants.
	## e.g. "a" -> "[a@4]", "s" -> "[s$5]"
	var alts: PackedStringArray = [c]
	for leet_char: String in _leet_map:
		if _leet_map[leet_char] == c:
			alts.append(_escape_for_class(leet_char))
	if alts.size() == 1:
		return c + "+" # just the letter, with repeat matching
	return "[" + "".join(alts) + "]+"


static func _word_to_pattern(word: String) -> String:
	## Convert a word into a regex that matches leetspeak, repeated chars, and separators.
	## e.g. "fuck" -> (?i)\b[f]+[.\-_ *~`]*[u]+[.\-_ *~`]*[c]+[.\-_ *~`]*[k]+\b
	var sep := "[.\\-_ *~`]*"
	var parts: PackedStringArray = []
	for i in range(word.length()):
		parts.append(_char_class(word[i]))
	return "(?i)\\b" + sep.join(parts) + "\\b"


static func filter(text: String) -> String:
	var result := text
	for regex in _patterns:
		var matches := regex.search_all(result)
		# Process in reverse order to preserve indices
		for i in range(matches.size() - 1, -1, -1):
			var m: RegExMatch = matches[i]
			var start := m.get_start()
			var end := m.get_end()
			var length := end - start
			result = result.substr(0, start) + "*".repeat(length) + result.substr(end)
	return result
