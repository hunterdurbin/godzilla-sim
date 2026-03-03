extends Node
## Downloads primary card artwork from the Godzilla TCG API.
## Add as an autoload or call start_download() from any scene.

signal download_complete(downloaded: int, skipped: int, failed: int)
signal progress_updated(current: int, total: int, card_number: String)

const API_BASE := "https://api.godzillatcg.com"
const CARDS_JSON_PATH := "res://CardContent/CardInfo/all_cards.json"
const ARTWORK_BASE_PATH := "user://CardContent/Artwork"
const CONCURRENT_DOWNLOADS := 15

var _cards: Array = []
var _next_index: int = 0
var _processed: int = 0
var _downloaded: int = 0
var _skipped: int = 0
var _failed: int = 0
var _is_running: bool = false
var _active_workers: int = 0
var _workers: Array[Dictionary] = []


func _ready() -> void:
	for i in CONCURRENT_DOWNLOADS:
		var http_images := HTTPRequest.new()
		var http_media := HTTPRequest.new()
		add_child(http_images)
		add_child(http_media)
		var worker := {
			"http_images": http_images,
			"http_media": http_media,
			"current_card": {},
		}
		http_images.request_completed.connect(_on_images_request_completed.bind(worker))
		http_media.request_completed.connect(_on_media_request_completed.bind(worker))
		_workers.append(worker)


func start_download() -> void:
	if _is_running:
		return
	_is_running = true
	_cards = _load_cards()
	_next_index = 0
	_processed = 0
	_downloaded = 0
	_skipped = 0
	_failed = 0
	_active_workers = 0
	print("[ArtworkDownloader] Starting download for %d cards..." % _cards.size())
	for i in mini(CONCURRENT_DOWNLOADS, _cards.size()):
		_process_next_card(_workers[i])


func _load_cards() -> Array:
	var file := FileAccess.open(CARDS_JSON_PATH, FileAccess.READ)
	if not file:
		push_error("[ArtworkDownloader] Could not open %s" % CARDS_JSON_PATH)
		return []
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("[ArtworkDownloader] JSON parse error: %s" % json.get_error_message())
		return []
	return json.data.get("cards", [])


func _get_set_number(card_number: String) -> String:
	return card_number.split("-")[0]


func _get_artwork_path(card_number: String) -> String:
	var set_number := _get_set_number(card_number)
	return ARTWORK_BASE_PATH.path_join(set_number).path_join("%s.png" % card_number)


func _process_next_card(worker: Dictionary) -> void:
	while _next_index < _cards.size():
		var card: Dictionary = _cards[_next_index]
		var card_number: String = card.get("card_number", "")
		var artwork_path := _get_artwork_path(card_number)
		_next_index += 1
		_processed += 1
		progress_updated.emit(_processed, _cards.size(), card_number)

		if FileAccess.file_exists(artwork_path):
			print("[ArtworkDownloader] [%d/%d] %s - already exists, skipping" % [
				_processed, _cards.size(), card_number
			])
			_skipped += 1
			continue

		# Found a card that needs downloading
		worker["current_card"] = card
		_active_workers += 1
		var card_id: int = card.get("id", 0)
		var url := "%s/cards/%d/images" % [API_BASE, card_id]
		print("[ArtworkDownloader] [%d/%d] %s - fetching image info..." % [
			_processed, _cards.size(), card_number
		])
		var err: int = worker["http_images"].request(url)
		if err != OK:
			push_error("[ArtworkDownloader] HTTP request error for %s: %d" % [card_number, err])
			_failed += 1
			_active_workers -= 1
			continue
		return

	# No more cards to process
	if _active_workers == 0:
		_finish()


func _on_images_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, worker: Dictionary) -> void:
	var card: Dictionary = worker["current_card"]
	var card_number: String = card.get("card_number", "")
	var card_id: int = card.get("id", 0)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[ArtworkDownloader] Failed to fetch images for %s (result=%d, code=%d)" % [
			card_number, result, response_code
		])
		_failed += 1
		_active_workers -= 1
		_process_next_card(worker)
		return

	var json := JSON.new()
	var err := json.parse(body.get_string_from_utf8())
	if err != OK:
		push_error("[ArtworkDownloader] JSON parse error for %s images" % card_number)
		_failed += 1
		_active_workers -= 1
		_process_next_card(worker)
		return

	var images: Array = json.data if json.data is Array else []

	# Find primary image
	var image_id: int = -1
	for img in images:
		if img.get("is_primary", false):
			image_id = img.get("id", -1)
			break

	# Fallback to first image
	if image_id == -1 and images.size() > 0:
		image_id = images[0].get("id", -1)

	if image_id == -1:
		push_error("[ArtworkDownloader] No image found for %s" % card_number)
		_failed += 1
		_active_workers -= 1
		_process_next_card(worker)
		return

	# Download the image
	var media_url := "%s/media/%d/%d" % [API_BASE, card_id, image_id]
	print("[ArtworkDownloader]   Downloading media/%d/%d..." % [card_id, image_id])
	err = worker["http_media"].request(media_url)
	if err != OK:
		push_error("[ArtworkDownloader] HTTP request error downloading %s: %d" % [card_number, err])
		_failed += 1
		_active_workers -= 1
		_process_next_card(worker)


func _on_media_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, worker: Dictionary) -> void:
	var card: Dictionary = worker["current_card"]
	var card_number: String = card.get("card_number", "")

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[ArtworkDownloader] Failed to download image for %s (result=%d, code=%d)" % [
			card_number, result, response_code
		])
		_failed += 1
		_active_workers -= 1
		_process_next_card(worker)
		return

	var artwork_path := _get_artwork_path(card_number)
	var set_number := _get_set_number(card_number)
	var set_dir := ARTWORK_BASE_PATH.path_join(set_number)

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(set_dir)

	# Save the image
	var file := FileAccess.open(artwork_path, FileAccess.WRITE)
	if not file:
		push_error("[ArtworkDownloader] Could not write to %s" % artwork_path)
		_failed += 1
		_active_workers -= 1
		_process_next_card(worker)
		return

	file.store_buffer(body)
	file.close()
	_downloaded += 1
	print("[ArtworkDownloader]   Saved %s" % artwork_path)

	_active_workers -= 1
	_process_next_card(worker)


func _finish() -> void:
	if not _is_running:
		return
	_is_running = false
	print("[ArtworkDownloader] Done! Downloaded: %d, Skipped: %d, Failed: %d" % [
		_downloaded, _skipped, _failed
	])
	download_complete.emit(_downloaded, _skipped, _failed)
