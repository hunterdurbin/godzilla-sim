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


# -- swap_in / final_path_for / cleanup_leftovers ----------------------------

func _replaced_dir() -> String:
	return _abs(TEST_DIR).path_join(UpdateInstaller.STAGING_DIR_NAME).path_join(UpdateInstaller.REPLACED_DIR_NAME)


func test_swap_in_file_parks_old_copy_in_staging() -> void:
	var target := _abs(TEST_DIR).path_join("sim.exe")
	var staged := _abs(TEST_DIR).path_join(".update_staging/extract/sim.exe")
	_write(target, "old")
	_write(staged, "new")
	assert_str(UpdateInstaller.swap_in(target, staged, target, _replaced_dir())).is_empty()
	assert_str(_read(target)).is_equal("new")
	assert_str(_read(_replaced_dir().path_join("sim.exe"))).is_equal("old")


func test_swap_in_bundle_dir() -> void:
	var target := _abs(TEST_DIR).path_join("sim.app")
	var staged := _abs(TEST_DIR).path_join(".update_staging/extract/sim.app")
	_write(target.path_join("Contents/MacOS/sim"), "old")
	_write(staged.path_join("Contents/MacOS/sim"), "new")
	assert_str(UpdateInstaller.swap_in(target, staged, target, _replaced_dir())).is_empty()
	assert_str(_read(target.path_join("Contents/MacOS/sim"))).is_equal("new")
	assert_str(_read(_replaced_dir().path_join("sim.app/Contents/MacOS/sim"))).is_equal("old")


func test_swap_in_channel_switch_renames_and_replaces_existing_stable() -> void:
	# Unstable running; a stale stable copy already sits beside it.
	var unstable := _abs(TEST_DIR).path_join("sim_unstable.exe")
	var stale_stable := _abs(TEST_DIR).path_join("sim.exe")
	var staged := _abs(TEST_DIR).path_join(".update_staging/extract/sim.exe")
	_write(unstable, "unstable")
	_write(stale_stable, "stale stable")
	_write(staged, "new stable")
	var target := {"kind": "file", "path": unstable, "dir": _abs(TEST_DIR)}
	var final_path := UpdateInstaller.final_path_for(target, staged, true)
	assert_str(final_path).is_equal(stale_stable)

	assert_str(UpdateInstaller.swap_in(unstable, staged, final_path, _replaced_dir())).is_empty()
	assert_str(_read(stale_stable)).is_equal("new stable")
	assert_bool(FileAccess.file_exists(unstable)).is_false()
	assert_str(_read(_replaced_dir().path_join("sim_unstable.exe"))).is_equal("unstable")
	assert_str(_read(_replaced_dir().path_join("sim.exe"))).is_equal("stale stable")


func test_final_path_keeps_renamed_target_on_same_channel() -> void:
	var target := {"kind": "file", "path": "/games/my_sim.exe", "dir": "/games"}
	assert_str(UpdateInstaller.final_path_for(target, "/games/.update_staging/extract/sim.exe", false)).is_equal("/games/my_sim.exe")


func test_swap_in_rolls_back_when_payload_missing() -> void:
	var unstable := _abs(TEST_DIR).path_join("sim_unstable.exe")
	var stable := _abs(TEST_DIR).path_join("sim.exe")
	_write(unstable, "unstable")
	_write(stable, "stable")
	var reason := UpdateInstaller.swap_in(unstable, _abs(TEST_DIR).path_join("missing.exe"), stable, _replaced_dir())
	assert_str(reason).is_not_empty()
	assert_str(_read(unstable)).is_equal("unstable")
	assert_str(_read(stable)).is_equal("stable")


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


func test_platform_asset_android_matches_either_channel_apk() -> void:
	var release := {"assets": [{"name": "godzilla_tcg_sim_unstable.apk", "browser_download_url": "https://x/u.apk", "size": 5}]}
	assert_str(UpdateChecker._get_platform_asset(release, "Android", false).get("url", "")).is_equal("https://x/u.apk")


# -- UpdateChecker.find_offers ------------------------------------------------

func _release(tag: String, draft := false) -> Dictionary:
	return {"tag_name": tag, "draft": draft, "html_url": "https://x/" + tag, "assets": [
		{"name": "godzilla_tcg_sim-windows.zip", "browser_download_url": "https://x/%s.zip" % tag, "size": 10},
	]}


func test_unstable_follows_newer_unstable_across_series() -> void:
	var offers := UpdateChecker.find_offers([
		_release("v0.1.12-unstable.14"), _release("v0.1.13-unstable.1"), _release("v0.1.12-unstable.9"),
	], "0.1.12-unstable.13", "Windows", false)
	assert_str(offers["same_channel"].get("tag", "")).is_equal("v0.1.13-unstable.1")
	assert_dict(offers["channel_switch"]).is_empty()


func test_unstable_offered_stable_of_own_series_or_later() -> void:
	var offers := UpdateChecker.find_offers([
		_release("v0.1.11-release-hotfix.1"), _release("v0.1.12-release"), _release("v0.1.12-release-hotfix.2"),
	], "0.1.12-unstable.13", "Windows", false)
	assert_dict(offers["same_channel"]).is_empty()
	assert_str(offers["channel_switch"].get("tag", "")).is_equal("v0.1.12-release-hotfix.2")
	assert_bool(offers["channel_switch"].get("switch_channel", false)).is_true()


func test_unstable_never_offered_older_series_stable() -> void:
	var offers := UpdateChecker.find_offers([_release("v0.1.11-release-hotfix.1")], "0.1.12-unstable.13", "Windows", false)
	assert_dict(offers).is_empty()


func test_unstable_gets_both_offers() -> void:
	var offers := UpdateChecker.find_offers([
		_release("v0.1.13-unstable.1"), _release("v0.1.12-release"),
	], "0.1.12-unstable.13", "Windows", false)
	assert_str(offers["same_channel"].get("tag", "")).is_equal("v0.1.13-unstable.1")
	assert_bool(offers["same_channel"].get("switch_channel", true)).is_false()
	assert_str(offers["channel_switch"].get("tag", "")).is_equal("v0.1.12-release")
	assert_str(UpdateChecker.skip_key(offers)).is_equal("v0.1.13-unstable.1,v0.1.12-release")


func test_stable_ignores_unstable_and_gets_no_switch() -> void:
	var offers := UpdateChecker.find_offers([
		_release("v0.1.13-unstable.1"), _release("v0.1.12-release-hotfix.1"),
	], "0.1.12-release", "Windows", false)
	assert_str(offers["same_channel"].get("tag", "")).is_equal("v0.1.12-release-hotfix.1")
	assert_dict(offers["channel_switch"]).is_empty()
	assert_str(UpdateChecker.skip_key(offers)).is_equal("v0.1.12-release-hotfix.1")


func test_release_gets_later_series_unstable_only_when_opted_in() -> void:
	var releases := [_release("v0.1.13-unstable.2"), _release("v0.1.12-unstable.20")]
	assert_dict(UpdateChecker.find_offers(releases, "0.1.12-release", "Windows", false, false)).is_empty()

	var offers := UpdateChecker.find_offers(releases, "0.1.12-release", "Windows", false, true)
	assert_dict(offers["same_channel"]).is_empty()
	assert_str(offers["channel_switch"].get("tag", "")).is_equal("v0.1.13-unstable.2")
	assert_str(offers["channel_switch"].get("channel", "")).is_equal("unstable")
	assert_bool(offers["channel_switch"].get("switch_channel", false)).is_true()


func test_release_never_offered_own_series_unstable() -> void:
	# 0.1.12-unstable.N predates 0.1.12-release, whatever N is.
	var offers := UpdateChecker.find_offers([_release("v0.1.12-unstable.20")], "0.1.12-release-hotfix.1", "Windows", false, true)
	assert_dict(offers).is_empty()


func test_opt_in_does_not_change_unstable_builds() -> void:
	var releases := [_release("v0.1.13-unstable.1"), _release("v0.1.12-release")]
	assert_dict(UpdateChecker.find_offers(releases, "0.1.12-unstable.13", "Windows", false, true)) \
		.is_equal(UpdateChecker.find_offers(releases, "0.1.12-unstable.13", "Windows", false, false))


func test_drafts_and_assetless_releases_are_ignored() -> void:
	var no_asset := _release("v0.1.12-unstable.20")
	no_asset["assets"] = []
	var offers := UpdateChecker.find_offers([
		_release("v0.1.12-unstable.19", true), no_asset, _release("v0.1.12-unstable.14"),
	], "0.1.12-unstable.13", "Windows", false)
	assert_str(offers["same_channel"].get("tag", "")).is_equal("v0.1.12-unstable.14")


func test_channel_switch_keeps_data_only_on_desktop_zip_builds() -> void:
	assert_bool(UpdateChecker.channel_switch_keeps_data("Windows", false)).is_true()
	assert_bool(UpdateChecker.channel_switch_keeps_data("macOS", false)).is_true()
	assert_bool(UpdateChecker.channel_switch_keeps_data("Linux", true)).is_false()
	assert_bool(UpdateChecker.channel_switch_keeps_data("Android", false)).is_false()
