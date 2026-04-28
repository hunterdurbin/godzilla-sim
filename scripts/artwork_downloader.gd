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


func _migrate_legacy_artwork() -> void:
	## One-time move: users updating from the pre-locale layout have artwork
	## at `user://CardContent/Artwork/<SET>/<CARD>.png`. Relocate every such
	## set folder into `user://CardContent/Artwork/en/<SET>/` so it's treated
	## as their existing EN pack. Idempotent — skips if nothing to migrate.
	var dir := DirAccess.open(ARTWORK_BASE_PATH)
	if dir == null:
		return
	var en_root := base_path_for_locale("en")
	var moved := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry != "." and entry != ".." and entry != "en" and entry != "ja":
			var src := ARTWORK_BASE_PATH.path_join(entry)
			var dst := en_root.path_join(entry)
			if _merge_dir_into(src, dst):
				moved += 1
		entry = dir.get_next()
	dir.list_dir_end()
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
	src_dir.list_dir_begin()
	var fname := src_dir.get_next()
	while not fname.is_empty():
		if not src_dir.current_is_dir():
			var dp := dst.path_join(fname)
			if not FileAccess.file_exists(dp):
				var rename_err := DirAccess.rename_absolute(src.path_join(fname), dp)
				if rename_err != OK:
					# Fall back to read/write copy (cross-volume edge case)
					var data := FileAccess.get_file_as_bytes(src.path_join(fname))
					var out := FileAccess.open(dp, FileAccess.WRITE)
					if out:
						out.store_buffer(data)
						out.close()
						DirAccess.remove_absolute(src.path_join(fname))
			else:
				# en/ already has this file; drop the legacy copy.
				DirAccess.remove_absolute(src.path_join(fname))
		fname = src_dir.get_next()
	src_dir.list_dir_end()
	# Try removing the (hopefully empty) src directory.
	DirAccess.remove_absolute(src)
	return true


func artwork_exists(card_number: String, locale: String) -> bool:
	var base_dir := base_path_for_locale(locale).path_join(_get_set_number(card_number))
	for ext in IMAGE_EXTENSIONS:
		if FileAccess.file_exists(base_dir.path_join("%s.%s" % [card_number, ext])):
			return true
	return false


func get_cached_count(locale: String) -> int:
	## Count how many card templates have at least one image cached on disk
	## for the given locale. Used by Options to render per-locale status.
	## SYSTEM placeholders (e.g. RAGE-MARKER) ship with built-in art and
	## aren't tracked by the downloader.
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
		var locale_root := base_path_for_locale(locale)
		_clear_tree(locale_root)
		print("[ArtworkDownloader] Cleared %s artwork from %s" % [locale, locale_root])


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


func start_download() -> void:
	if _is_running:
		return
	_is_running = true

	var locale: String = GameSettings.card_art_locale
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

	if missing.is_empty():
		_is_running = false
		download_complete.emit(0, skipped, 0)
		return

	var downloaded := 0
	var failed := 0

	if missing.size() == 1:
		var card_number := missing[0]
		progress_updated.emit(1, 1, card_number)
		if await _download_single(card_number, locale):
			downloaded = 1
		else:
			failed = 1
	else:
		var result := await _download_batch(missing, locale)
		downloaded = result.downloaded
		failed = result.failed

	_is_running = false
	print("[ArtworkDownloader] Done! locale=%s Downloaded: %d, Skipped: %d, Failed: %d" % [
		locale, downloaded, skipped, failed
	])
	download_complete.emit(downloaded, skipped, failed)


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
		push_error("[ArtworkDownloader] HTTP request error for %s: %d" % [card_number, err])
		return false

	var response: Array = await _http.request_completed
	var result: int = response[0]
	var response_code: int = response[1]
	var headers: PackedStringArray = response[2]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[ArtworkDownloader] Failed to download %s (result=%d, code=%d)" % [
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
		push_error("[ArtworkDownloader] Batch HTTP request error: %d" % err)
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
		push_error("[ArtworkDownloader] Batch download failed (result=%d, code=%d)" % [
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
