extends Node
## Downloads primary card artwork from the Godzilla TCG API.
## Uses batch endpoint (zip) for multiple cards, single endpoint for one card.
##
## Artwork is stored per-locale under `user://CardContent/Artwork/<locale>/<SET>/<CARD>.<ext>`.
## `start_download()` targets `GameSettings.card_art_locale` so the user can
## explicitly switch locales from Options before triggering a download.

signal download_complete(downloaded: int, skipped: int, failed: int)
signal progress_updated(current: int, total: int, card_number: String)
signal download_bytes_updated(downloaded_bytes: int, total_bytes: int)

const API_BASE := "https://api.godzillatcg.com"
const ARTWORK_BASE_PATH := "user://CardContent/Artwork"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const LEGACY_BASE_PATH := "user://CardContent/Artwork"  # pre-locale layout, read-only fallback
## Locale codes recognised by the API + on-disk layout. Anything else is
## coerced to "en" by _resolve_locale() at the boundary — catches stale
## settings.cfg values (e.g. a stray "ten") and fix-pool typos before they
## spawn orphan folders under ARTWORK_BASE_PATH.
const VALID_LOCALES: Array[String] = ["en", "ja"]

var _is_running: bool = false
var _http: HTTPRequest
var _batch_result: int = -1
var _batch_response_code: int = 0


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_migrate_legacy_artwork()


func base_path_for_locale(locale: String) -> String:
	return ARTWORK_BASE_PATH.path_join(locale)


func _resolve_locale(locale: String) -> String:
	## Coerce an arbitrary locale string into one of VALID_LOCALES, falling
	## back to "en" with a warning when the input is unknown. Apply at every
	## public/external boundary (start_download, apply_fix_pool, the public
	## artwork_exists/get_cached_count/clear_downloaded_artwork API) so a bad
	## value never reaches the API URL or disk-write path.
	if locale in VALID_LOCALES:
		return locale
	print("[ArtworkDownloader] Unknown locale '%s' — falling back to 'en'" % locale)
	return "en"


func _migrate_legacy_artwork() -> void:
	## One-time move: users updating from the pre-locale layout have artwork
	## at `user://CardContent/Artwork/<SET>/<CARD>.png`. Relocate every such
	## set folder into `user://CardContent/Artwork/en/<SET>/` so it's treated
	## as their existing EN pack. Idempotent — skips if nothing to migrate.
	var dir := DirAccess.open(ARTWORK_BASE_PATH)
	if dir == null:
		return
	# Snapshot directory entries before mutating. Windows' FindFirstFile/
	# FindNextFile is not safe to use concurrently with directory changes,
	# and the merge step both creates en/ and removes legacy folders.
	var legacy_entries: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry != "." and entry != ".." and entry != "en" and entry != "ja":
			legacy_entries.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	var en_root := base_path_for_locale("en")
	var moved := 0
	for legacy_entry in legacy_entries:
		var src := ARTWORK_BASE_PATH.path_join(legacy_entry)
		var dst := en_root.path_join(legacy_entry)
		if _merge_dir_into(src, dst):
			moved += 1
	if moved > 0:
		print("[ArtworkDownloader] Migrated %d legacy set folder(s) into en/" % moved)


func _merge_dir_into(src: String, dst: String) -> bool:
	## Move every file from `src` into `dst`, creating `dst` as needed.
	## If a file with the same name already exists in `dst`, keep the existing
	## one (don't overwrite whatever the user already has under en/). Removes
	## the now-empty src directory on success.
	DirAccess.make_dir_recursive_absolute(dst)
	var src_dir := DirAccess.open(src)
	if src_dir == null:
		return false
	# Snapshot file list before mutating the directory (see _migrate_legacy_artwork).
	var files_to_move: Array[String] = []
	src_dir.list_dir_begin()
	var fname := src_dir.get_next()
	while not fname.is_empty():
		if not src_dir.current_is_dir():
			files_to_move.append(fname)
		fname = src_dir.get_next()
	src_dir.list_dir_end()

	for fn in files_to_move:
		var sp := src.path_join(fn)
		var dp := dst.path_join(fn)
		if not FileAccess.file_exists(dp):
			var rename_err := DirAccess.rename_absolute(sp, dp)
			if rename_err != OK:
				# Fall back to read/write copy (cross-volume edge case)
				var data := FileAccess.get_file_as_bytes(sp)
				var out := FileAccess.open(dp, FileAccess.WRITE)
				if out:
					out.store_buffer(data)
					out.close()
					DirAccess.remove_absolute(sp)
		else:
			# en/ already has this file; drop the legacy copy.
			DirAccess.remove_absolute(sp)
	# Try removing the (hopefully empty) src directory.
	DirAccess.remove_absolute(src)
	return true


func artwork_exists(card_number: String, locale: String) -> bool:
	locale = _resolve_locale(locale)
	var base_dir := base_path_for_locale(locale).path_join(_get_set_number(card_number))
	for ext in IMAGE_EXTENSIONS:
		if FileAccess.file_exists(base_dir.path_join("%s.%s" % [card_number, ext])):
			return true
	# Legacy flat layout (pre-locale) is implicitly the EN pack. Falling back
	# to it for "en" stops a partially-failed migration from triggering a full
	# re-download when the files are still on disk under their old paths.
	if locale == "en":
		var legacy_dir := LEGACY_BASE_PATH.path_join(_get_set_number(card_number))
		for ext in IMAGE_EXTENSIONS:
			if FileAccess.file_exists(legacy_dir.path_join("%s.%s" % [card_number, ext])):
				return true
	return false


func count_cards_pending_update(locale: String) -> int:
	## Number of unique cards whose artwork for `locale` is either:
	##   (a) not on disk yet (cache miss), or
	##   (b) cached but queued for re-fetch via an unapplied
	##       CardArtworkFixPool entry whose `locales` includes this locale.
	## Used by Options to prompt the user after a locale switch.
	## De-duplicated — a card that's both missing AND in a pending fix-pool
	## entry counts once.
	locale = _resolve_locale(locale)
	var pending := {}  # set of card_id
	for card_id in CardData.CARD_TEMPLATES:
		var template: Dictionary = CardData.CARD_TEMPLATES[card_id]
		if template.get("card_type", -1) == CardEnums.CardType.RAGE:
			continue
		if not artwork_exists(card_id, locale):
			pending[card_id] = true
	var entries := CardArtworkFixPool.unapplied_entries(GameSettings.applied_artwork_fixes)
	for entry in entries:
		var entry_locales: Array = entry.locales
		if not (locale in entry_locales):
			continue
		for card_id in entry.card_ids:
			# Only count cards we actually know about — guards against a
			# fix-pool entry referencing a card that's since been removed.
			if CardData.CARD_TEMPLATES.has(card_id):
				pending[card_id] = true
	return pending.size()


func get_cached_count(locale: String) -> int:
	## Count how many card templates have at least one image cached on disk
	## for the given locale. Used by Options to render per-locale status.
	## SYSTEM placeholders (e.g. RAGE-MARKER) ship with built-in art and
	## aren't tracked by the downloader.
	locale = _resolve_locale(locale)
	var count := 0
	for card_id in CardData.CARD_TEMPLATES:
		var template: Dictionary = CardData.CARD_TEMPLATES[card_id]
		if template.get("card_type", -1) == CardEnums.CardType.RAGE:
			continue
		if artwork_exists(card_id, locale):
			count += 1
	return count


func clear_downloaded_artwork(locale: String = "") -> void:
	## Empty `locale` clears every locale's artwork (legacy behaviour).
	## Passing a specific locale clears just that subfolder.
	if locale.is_empty():
		_clear_tree(ARTWORK_BASE_PATH)
		print("[ArtworkDownloader] Cleared all downloaded artwork from %s" % ARTWORK_BASE_PATH)
	else:
		locale = _resolve_locale(locale)
		var locale_root := base_path_for_locale(locale)
		_clear_tree(locale_root)
		# artwork_exists() treats the legacy flat layout as the EN pack, so
		# wipe those folders too when clearing en/ — otherwise a re-download
		# would be silently skipped for cards still present in the old layout.
		if locale == "en":
			_clear_legacy_flat_layout()
		print("[ArtworkDownloader] Cleared %s artwork from %s" % [locale, locale_root])


func _clear_legacy_flat_layout() -> void:
	var dir := DirAccess.open(ARTWORK_BASE_PATH)
	if dir == null:
		return
	var legacy_dirs: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry != "." and entry != ".." and entry != "en" and entry != "ja":
			legacy_dirs.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for d in legacy_dirs:
		var legacy_path := ARTWORK_BASE_PATH.path_join(d)
		_remove_dir_contents(legacy_path)
		DirAccess.remove_absolute(legacy_path)


func _clear_tree(root: String) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry != "." and entry != "..":
			_remove_dir_contents(root.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _remove_dir_contents(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func apply_fix_pool() -> Dictionary:
	## Invalidate locally-cached artwork for any cards listed in
	## CardArtworkFixPool entries that haven't been applied yet on this
	## install. Each entry's `locales` field controls which language packs
	## are touched — most fixes are EN-only (the default), but an entry can
	## opt into multiple locales when the same art was republished across
	## packs.
	##
	## Returns a map `{ locale: Array[String] of card_numbers }` for every
	## non-active locale where we actually deleted a file. start_download()
	## consumes this to re-fetch those locales — otherwise start_download's
	## normal scan only covers the active locale and the deleted non-active
	## files would stay missing.
	var entries := CardArtworkFixPool.unapplied_entries(GameSettings.applied_artwork_fixes)
	if entries.is_empty():
		return {}

	var active_locale: String = _resolve_locale(GameSettings.card_art_locale)
	var post_fix: Dictionary = {}  # locale -> Array[String]
	var deleted := 0

	for entry in entries:
		var card_ids: Array = entry.card_ids
		var locales: Array = entry.locales
		for card_number in card_ids:
			for raw_loc in locales:
				var loc := _resolve_locale(raw_loc)
				var n := _delete_card_artwork_for_locale(card_number, loc)
				deleted += n
				# Only queue for post-fix re-fetch if we actually deleted
				# something AND the locale isn't the active one (which
				# start_download already handles via its missing-file scan).
				if n > 0 and loc != active_locale:
					var bucket: Array = post_fix.get(loc, [])
					if not bucket.has(card_number):
						bucket.append(card_number)
						post_fix[loc] = bucket

	# Mark every entry applied — even if nothing was on disk to delete
	# (fresh install, locale not cached, etc.). Idempotent; future runs no-op.
	for entry in entries:
		if not GameSettings.applied_artwork_fixes.has(entry.key):
			GameSettings.applied_artwork_fixes.append(entry.key)
	GameSettings.save()

	var post_count := 0
	for k in post_fix.keys():
		post_count += (post_fix[k] as Array).size()
	print("[ArtworkDownloader] Fix pool: %d entr(ies) applied; deleted %d file(s); %d non-active card-locale pair(s) queued for re-fetch" % [
		entries.size(), deleted, post_count
	])
	return post_fix


func _delete_card_artwork_for_locale(card_number: String, locale: String) -> int:
	## Delete cached image files for `card_number` in `locale`. Returns the
	## number of files removed (0 if nothing was cached). For "en" we also
	## clean the pre-locale legacy flat layout (ARTWORK_BASE_PATH/<set>/...)
	## defensively in case _migrate_legacy_artwork left something behind.
	var set_number := _get_set_number(card_number)
	var deleted := 0
	var card_dir := base_path_for_locale(locale).path_join(set_number)
	for ext in IMAGE_EXTENSIONS:
		var path := card_dir.path_join("%s.%s" % [card_number, ext])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			deleted += 1
	if locale == "en":
		var legacy_dir := ARTWORK_BASE_PATH.path_join(set_number)
		for ext in IMAGE_EXTENSIONS:
			var legacy_path := legacy_dir.path_join("%s.%s" % [card_number, ext])
			if FileAccess.file_exists(legacy_path):
				DirAccess.remove_absolute(legacy_path)
				deleted += 1
	return deleted


func start_download() -> void:
	# Defensive: if a previous run is still in flight (e.g. the user hit Skip
	# mid-download and is re-entering via Options > Re-download), cancel its
	# HTTP request and reset state. Without this, the re-entrant call no-ops
	# at the running guard and the LoadingScreen sits on "Preparing..." forever.
	if _is_running:
		push_warning("[ArtworkDownloader] start_download re-entered while a previous run was active; cancelling")
		_http.cancel_request()
		_is_running = false
	_is_running = true

	# Invalidate any cached files for cards listed in unapplied fix-pool
	# entries before the existence scan, so they're picked up as missing.
	# The returned map tells us which non-active locales also had files
	# wiped — start_download only fetches for the active locale on its own,
	# so we run targeted re-fetches for those locales at the end.
	var post_fix_by_locale := apply_fix_pool()

	# Flip the StatusLabel off "Preparing..." immediately. Without this, the
	# file-existence scan below leaves the bar idle until _download_batch's
	# polling loop fires, which can feel like a hang to users.
	download_bytes_updated.emit(0, 0)

	var locale: String = _resolve_locale(GameSettings.card_art_locale)
	var all_card_numbers := _get_all_card_numbers()
	var missing: Array[String] = []
	var skipped := 0

	for card_number in all_card_numbers:
		if artwork_exists(card_number, locale):
			skipped += 1
		else:
			missing.append(card_number)

	print("[ArtworkDownloader] locale=%s — %d cards total, %d cached, %d to download" % [
		locale, all_card_numbers.size(), skipped, missing.size()
	])

	var downloaded := 0
	var failed := 0

	if missing.size() == 1:
		var card_number := missing[0]
		progress_updated.emit(1, 1, card_number)
		if await _download_single(card_number, locale):
			downloaded = 1
		else:
			failed = 1
	elif missing.size() > 1:
		var result := await _download_batch(missing, locale)
		downloaded = result.downloaded
		failed = result.failed

	# Post-fix-pool catchup: re-fetch fix-pool cards for any non-active
	# locales that had cached files before apply_fix_pool() wiped them.
	# We deliberately fetch ONLY the specific deleted cards, not all missing
	# cards in the locale, so a user who's only partially downloaded that
	# locale doesn't get force-pulled into a full pack download here.
	for other_locale in post_fix_by_locale.keys():
		var cards_to_refetch: Array[String] = []
		for c in post_fix_by_locale[other_locale]:
			if c is String:
				cards_to_refetch.append(c)
		if cards_to_refetch.is_empty():
			continue
		var pass_stats := await _redownload_cards_for_locale(cards_to_refetch, other_locale)
		downloaded += pass_stats.downloaded
		failed += pass_stats.failed

	_is_running = false
	print("[ArtworkDownloader] Done! locale=%s Downloaded: %d, Skipped: %d, Failed: %d" % [
		locale, downloaded, skipped, failed
	])
	download_complete.emit(downloaded, skipped, failed)


func _redownload_cards_for_locale(card_numbers: Array[String], locale: String) -> Dictionary:
	## Targeted re-fetch of a specific card list in `locale`. Used as the
	## post-fix-pool catchup pass so non-active locales (e.g. ja while the
	## user is on en) refresh the cards we just invalidated.
	print("[ArtworkDownloader] Post-fix re-fetch: %d card(s) in locale=%s" % [
		card_numbers.size(), locale
	])
	if card_numbers.is_empty():
		return {"downloaded": 0, "failed": 0}
	if card_numbers.size() == 1:
		progress_updated.emit(1, 1, card_numbers[0])
		if await _download_single(card_numbers[0], locale):
			return {"downloaded": 1, "failed": 0}
		return {"downloaded": 0, "failed": 1}
	return await _download_batch(card_numbers, locale)


func _get_all_card_numbers() -> Array[String]:
	## Skip engine-internal SYSTEM placeholders (e.g. RAGE-MARKER) — those
	## ship with built-in default art and aren't hosted by the downloader.
	var card_numbers: Array[String] = []
	for card_id in CardData.CARD_TEMPLATES:
		var template: Dictionary = CardData.CARD_TEMPLATES[card_id]
		if template.get("card_type", -1) == CardEnums.CardType.RAGE:
			continue
		card_numbers.append(card_id)
	return card_numbers


func _get_set_number(card_number: String) -> String:
	return card_number.split("-")[0]


func _save_artwork(card_number: String, data: PackedByteArray, extension: String, locale: String) -> bool:
	var set_dir := base_path_for_locale(locale).path_join(_get_set_number(card_number))
	DirAccess.make_dir_recursive_absolute(set_dir)

	var artwork_path := set_dir.path_join("%s.%s" % [card_number, extension])
	var file := FileAccess.open(artwork_path, FileAccess.WRITE)
	if not file:
		push_error("[ArtworkDownloader] Could not write to %s" % artwork_path)
		return false

	file.store_buffer(data)
	file.close()
	print("[ArtworkDownloader]   Saved %s" % artwork_path)
	return true


func _download_single(card_number: String, locale: String) -> bool:
	var url := "%s/media/by-number/%s?locale=%s&thumbnail=false" % [API_BASE, card_number, locale]
	print("[ArtworkDownloader] Downloading %s (%s)..." % [card_number, locale])

	var err := _http.request(url)
	if err != OK:
		# Network failures are routine (offline play) — not error-channel.
		print("[ArtworkDownloader] HTTP request error for %s: %d" % [card_number, err])
		return false

	var response: Array = await _http.request_completed
	var result: int = response[0]
	var response_code: int = response[1]
	var headers: PackedStringArray = response[2]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		# Network failures are routine (offline play) — not error-channel.
		print("[ArtworkDownloader] Failed to download %s (result=%d, code=%d)" % [
			card_number, result, response_code
		])
		return false

	var ext := _get_extension_from_headers(headers, "png")
	return _save_artwork(card_number, body, ext, locale)


func _on_batch_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_batch_result = result
	_batch_response_code = response_code


func _download_batch(card_numbers: Array[String], locale: String) -> Dictionary:
	var url := "%s/media/by-number/batch" % API_BASE
	var json_body := JSON.stringify({
		"card_numbers": card_numbers,
		"locale": locale,
		"thumbnail": false,
	})
	var request_headers := ["Content-Type: application/json"]
	var temp_path := "user://CardContent/_temp_batch.zip"
	DirAccess.make_dir_recursive_absolute("user://CardContent")

	print("[ArtworkDownloader] Batch downloading %d cards (%s)..." % [card_numbers.size(), locale])

	# Download directly to file to avoid buffering 100+ MB in memory
	_batch_result = -1
	_batch_response_code = 0
	_http.download_file = temp_path
	_http.request_completed.connect(_on_batch_request_completed, CONNECT_ONE_SHOT)

	var err := _http.request(url, request_headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		# Network failures are routine (offline play) — not error-channel.
		print("[ArtworkDownloader] Batch HTTP request error: %d" % err)
		_http.download_file = ""
		return {"downloaded": 0, "failed": card_numbers.size()}

	# Poll download progress until complete
	while _batch_result == -1:
		var body_size := _http.get_body_size()
		var downloaded_bytes := _http.get_downloaded_bytes()
		download_bytes_updated.emit(downloaded_bytes, body_size)
		await get_tree().process_frame

	_http.download_file = ""

	if _batch_result != HTTPRequest.RESULT_SUCCESS or _batch_response_code != 200:
		# Network failures are routine (offline play) — not error-channel.
		print("[ArtworkDownloader] Batch download failed (result=%d, code=%d)" % [
			_batch_result, _batch_response_code
		])
		DirAccess.remove_absolute(temp_path)
		return {"downloaded": 0, "failed": card_numbers.size()}

	return _extract_zip(temp_path, card_numbers, locale)


func _extract_zip(temp_path: String, card_numbers: Array[String], locale: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(temp_path)
	if err != OK:
		push_error("[ArtworkDownloader] Could not open zip (error=%d)" % err)
		DirAccess.remove_absolute(temp_path)
		return {"downloaded": 0, "failed": card_numbers.size()}

	var downloaded := 0
	var failed := 0
	var files := reader.get_files()
	var total := files.size()

	for i in total:
		var entry_name: String = files[i]
		# Entry format: {card_number}.{ext}
		var dot_pos := entry_name.rfind(".")
		if dot_pos == -1:
			failed += 1
			continue
		var card_number := entry_name.substr(0, dot_pos)
		var ext := entry_name.substr(dot_pos + 1)

		progress_updated.emit(i + 1, total, card_number)
		var data := reader.read_file(entry_name)
		if _save_artwork(card_number, data, ext, locale):
			downloaded += 1
		else:
			failed += 1

	# Cards not in zip (no image on server for this locale) count as failed;
	# card.gd's render path will fall back to the en/ copy if present.
	var missing_from_zip := card_numbers.size() - downloaded - failed
	if missing_from_zip > 0:
		print("[ArtworkDownloader] %d cards had no image on server (locale=%s)" % [missing_from_zip, locale])
		failed += missing_from_zip

	reader.close()
	DirAccess.remove_absolute(temp_path)
	return {"downloaded": downloaded, "failed": failed}


func _get_extension_from_headers(headers: PackedStringArray, fallback: String) -> String:
	for header in headers:
		var lower := header.to_lower()
		if lower.begins_with("content-type:"):
			var content_type := lower.split(":")[1].strip_edges()
			if "jpeg" in content_type or "jpg" in content_type:
				return "jpg"
			elif "png" in content_type:
				return "png"
			elif "webp" in content_type:
				return "webp"
			break
	return fallback
