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
