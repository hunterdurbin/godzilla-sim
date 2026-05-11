class_name CardArtworkFixPool
extends RefCounted

## Card IDs whose cached artwork must be invalidated on the first launch
## after a release. ArtworkDownloader.apply_fix_pool() deletes the stale
## local files so start_download() re-fetches the corrected version.
##
## Add a new entry per release that ships translation/art corrections.
## Keys are arbitrary stable strings — once shipped, do NOT rename them
## (existing clients track which keys they've already applied).
##
## Convention: "<version>_<short-summary>"
const ENTRIES := {
	"v0.1.12-unstable.2_ebp04_translation_fixes": {
		"description": "Corrected EBP04-013 / EBP04-021 / EBP04-028 / EBP04-082 effect translations",
		"card_ids": ["EBP04-013", "EBP04-021", "EBP04-028", "EBP04-082"],
	},
	"v0.1.12-unstable.3_ebp04_moguera_trait_fix": {
		"description": "Correct EBP04-053 Weapon trait",
		"card_ids": ["EBP04-053"],
	},
	"v0.1.12-unstable.5_ebp04_full_en_set": {
		"description": "EBP04 full set republished in English",
		"card_ids": [
			"EBP04-001", "EBP04-002", "EBP04-003", "EBP04-004", "EBP04-005",
			"EBP04-006", "EBP04-007", "EBP04-008", "EBP04-009", "EBP04-010",
			"EBP04-011", "EBP04-012", "EBP04-013", "EBP04-014", "EBP04-015",
			"EBP04-016", "EBP04-017", "EBP04-018", "EBP04-019", "EBP04-020",
			"EBP04-021", "EBP04-022", "EBP04-023", "EBP04-024", "EBP04-025",
			"EBP04-026", "EBP04-027", "EBP04-028", "EBP04-029", "EBP04-030",
			"EBP04-031", "EBP04-032", "EBP04-033", "EBP04-034", "EBP04-035",
			"EBP04-036", "EBP04-037", "EBP04-038", "EBP04-039", "EBP04-040",
			"EBP04-041", "EBP04-042", "EBP04-043", "EBP04-044", "EBP04-045",
			"EBP04-046", "EBP04-047", "EBP04-048", "EBP04-049", "EBP04-050",
			"EBP04-051", "EBP04-052", "EBP04-053", "EBP04-054", "EBP04-055",
			"EBP04-056", "EBP04-057", "EBP04-058", "EBP04-059", "EBP04-060",
			"EBP04-061", "EBP04-062", "EBP04-063", "EBP04-064", "EBP04-065",
			"EBP04-066", "EBP04-067", "EBP04-068", "EBP04-069", "EBP04-070",
			"EBP04-071", "EBP04-072", "EBP04-073", "EBP04-074", "EBP04-075",
			"EBP04-076", "EBP04-077", "EBP04-078", "EBP04-079", "EBP04-080",
			"EBP04-081", "EBP04-082", "EBP04-083", "EBP04-084", "EBP04-085",
			"EBP04-086", "EBP04-087", "EBP04-088", "EBP04-089", "EBP04-T01",
		],
	},
}


static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in ENTRIES.keys():
		keys.append(k)
	return keys


static func card_ids_for_unapplied(applied: Array) -> Array[String]:
	## Returns the union of card_ids across every entry whose key is NOT in
	## `applied`. De-duplicated, in insertion order.
	var seen := {}
	var out: Array[String] = []
	for key in ENTRIES.keys():
		if applied.has(key):
			continue
		var entry: Dictionary = ENTRIES[key]
		for cid in entry.get("card_ids", []):
			if not seen.has(cid):
				seen[cid] = true
				out.append(cid)
	return out
