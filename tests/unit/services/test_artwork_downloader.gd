extends GdUnitTestSuite

## ArtworkDownloader payload/file validation. A batch zip can carry a
## zero-length entry (server still rendering); saving it verbatim leaves a
## 0-byte .png on disk that every reader then treats as cached artwork and
## card.gd spams "Failed to load image" on each render.

const TEST_DIR := "user://_test_artwork"

# PNG signature + IHDR chunk header (16 bytes) — enough for the magic-byte check.
const PNG_HEAD := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]


func before() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func after() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(TEST_DIR)


func _write(name: String, bytes: Array) -> String:
	var path := TEST_DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(PackedByteArray(bytes))
	f.close()
	return path


func test_empty_payload_is_rejected() -> void:
	assert_bool(ArtworkDownloader.is_valid_image_payload(PackedByteArray())).is_false()


func test_png_payload_is_accepted() -> void:
	assert_bool(ArtworkDownloader.is_valid_image_payload(PackedByteArray(PNG_HEAD))).is_true()


func test_html_error_body_is_rejected() -> void:
	assert_bool(ArtworkDownloader.is_valid_image_payload("<html>404</html>".to_utf8_buffer())).is_false()


func test_zero_byte_file_does_not_count_as_cached_artwork() -> void:
	var path := _write("EMPTY.png", [])
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_bool(ArtworkDownloader.is_valid_artwork_file(path)).is_false()


func test_non_empty_file_counts_as_cached_artwork() -> void:
	var path := _write("OK.png", PNG_HEAD)
	assert_bool(ArtworkDownloader.is_valid_artwork_file(path)).is_true()


func test_missing_file_is_not_valid_artwork() -> void:
	assert_bool(ArtworkDownloader.is_valid_artwork_file(TEST_DIR.path_join("nope.png"))).is_false()
