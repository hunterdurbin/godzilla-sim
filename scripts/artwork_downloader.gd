extends Node
## Downloads primary card artwork from the Godzilla TCG API.
## Uses batch endpoint (zip) for multiple cards, single endpoint for one card.

signal download_complete(downloaded: int, skipped: int, failed: int)
signal progress_updated(current: int, total: int, card_number: String)
signal download_bytes_updated(downloaded_bytes: int, total_bytes: int)

const API_BASE := "http://localhost:8080"
const ARTWORK_BASE_PATH := "user://CardContent/Artwork"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

var _is_running: bool = false
var _http: HTTPRequest
var _batch_result: int = -1
var _batch_response_code: int = 0


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


func start_download() -> void:
	if _is_running:
		return
	_is_running = true

	var all_card_numbers := _get_all_card_numbers()
	var missing: Array[String] = []
	var skipped := 0

	for card_number in all_card_numbers:
		if _artwork_exists(card_number):
			skipped += 1
		else:
			missing.append(card_number)

	print("[ArtworkDownloader] %d cards total, %d cached, %d to download" % [
		all_card_numbers.size(), skipped, missing.size()
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
		if await _download_single(card_number):
			downloaded = 1
		else:
			failed = 1
	else:
		var result := await _download_batch(missing)
		downloaded = result.downloaded
		failed = result.failed

	_is_running = false
	print("[ArtworkDownloader] Done! Downloaded: %d, Skipped: %d, Failed: %d" % [
		downloaded, skipped, failed
	])
	download_complete.emit(downloaded, skipped, failed)


func _get_all_card_numbers() -> Array[String]:
	var card_numbers: Array[String] = []
	for card_id in CardData.CARD_TEMPLATES:
		card_numbers.append(card_id)
	return card_numbers


func _get_set_number(card_number: String) -> String:
	return card_number.split("-")[0]


func _artwork_exists(card_number: String) -> bool:
	var set_number := _get_set_number(card_number)
	var base_dir := ARTWORK_BASE_PATH.path_join(set_number)
	for ext in IMAGE_EXTENSIONS:
		if FileAccess.file_exists(base_dir.path_join("%s.%s" % [card_number, ext])):
			return true
	return false


func _save_artwork(card_number: String, data: PackedByteArray, extension: String) -> bool:
	var set_number := _get_set_number(card_number)
	var set_dir := ARTWORK_BASE_PATH.path_join(set_number)
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


func _download_single(card_number: String) -> bool:
	var url := "%s/media/by-number/%s" % [API_BASE, card_number]
	print("[ArtworkDownloader] Downloading %s..." % card_number)

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
	return _save_artwork(card_number, body, ext)


func _on_batch_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_batch_result = result
	_batch_response_code = response_code


func _download_batch(card_numbers: Array[String]) -> Dictionary:
	var url := "%s/media/by-number/batch" % API_BASE
	var json_body := JSON.stringify({"card_numbers": card_numbers})
	var request_headers := ["Content-Type: application/json"]
	var temp_path := "user://CardContent/_temp_batch.zip"
	DirAccess.make_dir_recursive_absolute("user://CardContent")

	print("[ArtworkDownloader] Batch downloading %d cards..." % card_numbers.size())

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

	return _extract_zip(temp_path, card_numbers)


func _extract_zip(temp_path: String, card_numbers: Array[String]) -> Dictionary:
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
		if _save_artwork(card_number, data, ext):
			downloaded += 1
		else:
			failed += 1

	# Cards not in zip (no image on server) count as failed
	var missing_from_zip := card_numbers.size() - downloaded - failed
	if missing_from_zip > 0:
		print("[ArtworkDownloader] %d cards had no image on server" % missing_from_zip)
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
