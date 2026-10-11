extends GdUnitTestSuite

## UpdateInstaller's file-level contract (payload discovery, extraction,
## swap + rollback, boot cleanup) and UpdateChecker's asset metadata parse.
## Everything runs against fake install trees under user://.

const TEST_DIR := "user://_test_update_installer"


func before_test() -> void:
	UpdateInstaller.remove_recursive(_abs(TEST_DIR))
	DirAccess.make_dir_recursive_absolute(_abs(TEST_DIR))


func after_test() -> void:
	UpdateInstaller.remove_recursive(_abs(TEST_DIR))


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# -- install_target -----------------------------------------------------------

func test_install_target_mac_is_the_bundle() -> void:
	var t := UpdateInstaller.install_target("/Users/x/Games/sim.app/Contents/MacOS/sim", "macOS")
	assert_str(t.get("kind", "")).is_equal("bundle")
	assert_str(t.get("path", "")).is_equal("/Users/x/Games/sim.app")
	assert_str(t.get("dir", "")).is_equal("/Users/x/Games")


func test_install_target_mac_outside_bundle_is_unsupported() -> void:
	assert_dict(UpdateInstaller.install_target("/usr/local/bin/sim", "macOS")).is_empty()


func test_install_target_windows_is_the_exe() -> void:
	var t := UpdateInstaller.install_target("C:/Games/sim/sim.exe", "Windows")
	assert_str(t.get("kind", "")).is_equal("file")
	assert_str(t.get("path", "")).is_equal("C:/Games/sim/sim.exe")
	assert_str(t.get("dir", "")).is_equal("C:/Games/sim")


# -- find_payload -------------------------------------------------------------

func test_find_payload_picks_platform_exe() -> void:
	var root := _abs(TEST_DIR).path_join("extract")
	_write(root.path_join("sim.x86_64"), "linux")
	_write(root.path_join("README.txt"), "x")
	assert_str(UpdateInstaller.find_payload(root, "file", "Linux")).is_equal(root.path_join("sim.x86_64"))
	assert_str(UpdateInstaller.find_payload(root, "file", "Windows")).is_empty()


func test_find_payload_bundle() -> void:
	var root := _abs(TEST_DIR).path_join("extract")
	_write(root.path_join("sim.app/Contents/MacOS/sim"), "mac")
	assert_str(UpdateInstaller.find_payload(root, "bundle", "macOS")).is_equal(root.path_join("sim.app"))


func test_find_payload_refuses_ambiguous_archives() -> void:
	var root := _abs(TEST_DIR).path_join("extract")
	_write(root.path_join("a.exe"), "1")
	_write(root.path_join("b.exe"), "2")
	assert_str(UpdateInstaller.find_payload(root, "file", "Windows")).is_empty()


# -- extract_zip --------------------------------------------------------------

func test_extract_zip_writes_nested_entries() -> void:
	var zip_path := _abs(TEST_DIR).path_join("pkg.zip")
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file("sim.app/Contents/MacOS/sim")
	packer.write_file("binary".to_utf8_buffer())
	packer.close_file()
	packer.start_file("sim.app/Contents/Info.plist")
	packer.write_file("plist".to_utf8_buffer())
	packer.close_file()
	packer.close()

	var dest := _abs(TEST_DIR).path_join("extract")
	assert_str(UpdateInstaller.extract_zip(zip_path, dest)).is_empty()
	assert_str(_read(dest.path_join("sim.app/Contents/MacOS/sim"))).is_equal("binary")
	assert_str(_read(dest.path_join("sim.app/Contents/Info.plist"))).is_equal("plist")


func test_extract_zip_rejects_parent_escape() -> void:
	var zip_path := _abs(TEST_DIR).path_join("evil.zip")
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file("../escape.txt")
	packer.write_file("x".to_utf8_buffer())
	packer.close_file()
	packer.close()

	var dest := _abs(TEST_DIR).path_join("extract")
	assert_str(UpdateInstaller.extract_zip(zip_path, dest)).is_not_empty()
	assert_bool(FileAccess.file_exists(_abs(TEST_DIR).path_join("escape.txt"))).is_false()


# -- swap_in / cleanup_leftovers ---------------------------------------------

func test_swap_in_file_keeps_old_copy() -> void:
	var target := _abs(TEST_DIR).path_join("sim.exe")
	var staged := _abs(TEST_DIR).path_join(".update_staging/extract/sim.exe")
	_write(target, "old")
	_write(staged, "new")
	assert_str(UpdateInstaller.swap_in(target, staged)).is_empty()
	assert_str(_read(target)).is_equal("new")
	assert_str(_read(target + UpdateInstaller.OLD_SUFFIX)).is_equal("old")


func test_swap_in_bundle_dir() -> void:
	var target := _abs(TEST_DIR).path_join("sim.app")
	var staged := _abs(TEST_DIR).path_join(".update_staging/extract/sim.app")
	_write(target.path_join("Contents/MacOS/sim"), "old")
	_write(staged.path_join("Contents/MacOS/sim"), "new")
	assert_str(UpdateInstaller.swap_in(target, staged)).is_empty()
	assert_str(_read(target.path_join("Contents/MacOS/sim"))).is_equal("new")
	assert_str(_read(target + ".old/Contents/MacOS/sim")).is_equal("old")


func test_swap_in_rolls_back_when_payload_missing() -> void:
	var target := _abs(TEST_DIR).path_join("sim.exe")
	_write(target, "old")
	var reason := UpdateInstaller.swap_in(target, _abs(TEST_DIR).path_join("missing.exe"))
	assert_str(reason).is_not_empty()
	assert_str(_read(target)).is_equal("old")
	assert_bool(FileAccess.file_exists(target + UpdateInstaller.OLD_SUFFIX)).is_false()


func test_cleanup_leftovers_removes_old_and_staging() -> void:
	var dir := _abs(TEST_DIR)
	var target := dir.path_join("sim.app")
	_write(target.path_join("Contents/MacOS/sim"), "current")
	_write(target + ".old/Contents/MacOS/sim", "previous")
	_write(dir.path_join(UpdateInstaller.STAGING_DIR_NAME).path_join("pkg.zip"), "partial")

	UpdateInstaller.cleanup_leftovers({"kind": "bundle", "path": target, "dir": dir})
	assert_bool(DirAccess.dir_exists_absolute(target + ".old")).is_false()
	assert_bool(DirAccess.dir_exists_absolute(dir.path_join(UpdateInstaller.STAGING_DIR_NAME))).is_false()
	assert_str(_read(target.path_join("Contents/MacOS/sim"))).is_equal("current")


func test_remove_recursive_deletes_hidden_files() -> void:
	var old_bundle := _abs(TEST_DIR).path_join("sim.app.old")
	_write(old_bundle.path_join("Contents/MacOS/sim"), "previous")
	_write(old_bundle.path_join(".DS_Store"), "finder")
	_write(old_bundle.path_join("Contents/.hidden_dir/file"), "x")
	UpdateInstaller.remove_recursive(old_bundle)
	assert_bool(DirAccess.dir_exists_absolute(old_bundle)).is_false()


# -- UpdateChecker asset metadata --------------------------------------------

func test_platform_asset_carries_size_and_digest() -> void:
	var release := {"assets": [
		{"name": "godzilla_tcg_sim-linux.zip", "browser_download_url": "https://x/linux.zip", "size": 1234, "digest": "sha256:abc123"},
		{"name": "godzilla_tcg_sim.flatpak", "browser_download_url": "https://x/app.flatpak", "size": 99},
	]}
	var asset: Dictionary = UpdateChecker._get_platform_asset(release, "Linux", false)
	assert_str(asset.get("url", "")).is_equal("https://x/linux.zip")
	assert_int(asset.get("size", 0)).is_equal(1234)
	assert_str(asset.get("sha256", "")).is_equal("abc123")

	var flatpak: Dictionary = UpdateChecker._get_platform_asset(release, "Linux", true)
	assert_str(flatpak.get("url", "")).is_equal("https://x/app.flatpak")
	assert_str(flatpak.get("sha256", "x")).is_empty()


func test_platform_asset_missing_is_empty() -> void:
	assert_dict(UpdateChecker._get_platform_asset({"assets": []}, "Windows", false)).is_empty()
	assert_dict(UpdateChecker._get_platform_asset({"assets": []}, "Android", false)).is_empty()
