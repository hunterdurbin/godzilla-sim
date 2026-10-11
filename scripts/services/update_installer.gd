class_name UpdateInstaller
extends Node
## In-app updater for the desktop zip builds (Windows / macOS / Linux).
##
## Pipeline: download the release zip into a staging dir INSIDE the install
## dir (so the final rename never crosses filesystems) -> verify size/sha256
## -> extract -> wait for the player -> swap + relaunch.
##
## The swap is deferred to restart() on purpose: Godot reads the PCK lazily
## by path, so once the running exe/bundle is renamed (or replaced) any
## not-yet-cached resource load would read the wrong file. Swapping right
## before create_process + quit leaves no window for that.
##
## Swap contract: rename the running target to `<target>.old`, move the new
## payload into its place, roll back on failure. The next boot deletes the
## `.old` leftover and the staging dir via cleanup_leftovers().

signal progress(downloaded: int, total: int)
signal status_changed(stage: String)
signal failed(reason: String)
signal ready_to_restart()

const STAGING_DIR_NAME := ".update_staging"
const OLD_SUFFIX := ".old"
const STAGE_DOWNLOADING := "downloading"
const STAGE_INSTALLING := "installing"
const EXEC_PERMISSIONS := FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER \
		| FileAccess.UNIX_EXECUTE_OWNER | FileAccess.UNIX_READ_GROUP \
		| FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER \
		| FileAccess.UNIX_EXECUTE_OTHER

var busy: bool = false

var _http: HTTPRequest
var _info: Dictionary = {}
var _target: Dictionary = {}
var _staging: String = ""
var _payload: String = ""


# -- Static helpers -----------------------------------------------------------

## True when this build can replace itself: an exported desktop zip build,
## outside the Flatpak sandbox, with a writable install dir.
static func can_self_update() -> bool:
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return false
	if not OS.get_name() in ["Windows", "macOS", "Linux"]:
		return false
	if FileAccess.file_exists("/.flatpak-info"):
		return false
	var target := install_target()
	return not target.is_empty() and is_dir_writable(target["dir"])


## What gets replaced. Windows/Linux: the exe itself (PCK is embedded).
## macOS: the whole .app bundle (exe lives at X.app/Contents/MacOS/<exe>).
static func install_target(exe_path: String = OS.get_executable_path(), os_name: String = OS.get_name()) -> Dictionary:
	if exe_path.is_empty():
		return {}
	if os_name == "macOS":
		var bundle := exe_path.get_base_dir().get_base_dir().get_base_dir()
		if not bundle.ends_with(".app"):
			return {}
		return {"kind": "bundle", "path": bundle, "dir": bundle.get_base_dir()}
	return {"kind": "file", "path": exe_path, "dir": exe_path.get_base_dir()}


static func is_dir_writable(dir_path: String) -> bool:
	var probe := dir_path.path_join(".update_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## The single top-level payload in an extracted release zip: a `*.app` dir
## for bundles, else a `*.exe` (Windows) / `*.x86_64` (Linux) file. Returns
## "" when there is none or more than one (ambiguous — refuse to guess).
static func find_payload(extract_dir: String, kind: String, os_name: String = OS.get_name()) -> String:
	var dir := DirAccess.open(extract_dir)
	if dir == null:
		return ""
	var found: Array[String] = []
	if kind == "bundle":
		for d in dir.get_directories():
			if d.ends_with(".app"):
				found.append(d)
	else:
		var ext := "exe" if os_name == "Windows" else "x86_64"
		for f in dir.get_files():
			if f.get_extension() == ext:
				found.append(f)
	if found.size() != 1:
		return ""
	return extract_dir.path_join(found[0])


## Extracts every entry of `zip_path` under `dest_dir`. Rejects absolute and
## parent-escaping entry names. Returns "" on success, else a reason.
static func extract_zip(zip_path: String, dest_dir: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return "could not open the downloaded archive"
	DirAccess.make_dir_recursive_absolute(dest_dir)
	for entry in reader.get_files():
		if entry.is_absolute_path() or entry.begins_with("/") or ".." in entry.split("/"):
			reader.close()
			return "archive contains an unsafe path: %s" % entry
		var out_path := dest_dir.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(out_path)
			continue
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			reader.close()
			return "could not write %s" % entry
		f.store_buffer(reader.read_file(entry))
		f.close()
	reader.close()
	return ""


## ZIPReader doesn't restore Unix modes; re-mark the launchable files.
static func restore_exec_bits(payload: String, kind: String) -> void:
	if kind == "bundle":
		var macos_dir := payload.path_join("Contents/MacOS")
		var dir := DirAccess.open(macos_dir)
		if dir == null:
			return
		for f in dir.get_files():
			FileAccess.set_unix_permissions(macos_dir.path_join(f), EXEC_PERMISSIONS)
	elif OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(payload, EXEC_PERMISSIONS)


## Moves `new_path` over `target_path`, keeping the original at
## `<target>.old`. Rolls back if the second rename fails. Returns "" on
## success, else a reason.
static func swap_in(target_path: String, new_path: String) -> String:
	var old := target_path + OLD_SUFFIX
	remove_recursive(old)
	if DirAccess.rename_absolute(target_path, old) != OK:
		return "could not move the current install aside"
	if DirAccess.rename_absolute(new_path, target_path) != OK:
		DirAccess.rename_absolute(old, target_path)
		return "could not move the new version into place"
	return ""


## Deletes what a previous update left behind: the `.old` target and the
## staging dir. Safe to call every boot; failures (e.g. the old Windows exe
## still exiting) are retried next boot.
static func cleanup_leftovers(target: Dictionary = {}) -> void:
	if target.is_empty():
		if OS.has_feature("editor") or not OS.has_feature("template"):
			return
		target = install_target()
		if target.is_empty():
			return
	remove_recursive(String(target["path"]) + OLD_SUFFIX)
	remove_recursive(String(target["dir"]).path_join(STAGING_DIR_NAME))


static func remove_recursive(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		remove_recursive(path.path_join(d))
	DirAccess.remove_absolute(path)


# -- Pipeline -----------------------------------------------------------------

## `info` = UpdateChecker.pending_update ({download_url, size, sha256, ...}).
func start(info: Dictionary) -> void:
	if busy:
		return
	_info = info
	_target = install_target()
	if _target.is_empty():
		failed.emit("unsupported install layout")
		return
	busy = true
	_staging = String(_target["dir"]).path_join(STAGING_DIR_NAME)
	remove_recursive(_staging)
	DirAccess.make_dir_recursive_absolute(_staging)

	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_file = _staging.path_join("pkg.zip")
	_http.request_completed.connect(_on_download_completed)
	add_child(_http)
	var err := _http.request(String(info.get("download_url", "")))
	if err != OK:
		_fail("download could not start (error %d)" % err)
		return
	status_changed.emit(STAGE_DOWNLOADING)
	set_process(true)


func cancel() -> void:
	if _http:
		_http.cancel_request()
	_reset()


## Swaps the staged payload in and relaunches. Only valid after
## ready_to_restart. On success this quits the app; on failure it emits
## `failed` with the install rolled back.
func restart() -> void:
	var reason := swap_in(_target["path"], _payload)
	if not reason.is_empty():
		_fail(reason)
		return
	var path: String = _target["path"]
	if _target["kind"] == "bundle":
		OS.create_process("/usr/bin/open", ["-n", path])
	else:
		OS.create_process(path, [])
	get_tree().quit()


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _http == null:
		return
	var total := _http.get_body_size()
	if total <= 0:
		total = int(_info.get("size", 0))
	progress.emit(_http.get_downloaded_bytes(), total)


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail("download failed (result %d, HTTP %d)" % [result, response_code])
		return
	status_changed.emit(STAGE_INSTALLING)
	# Let the label repaint before the synchronous verify/extract.
	await get_tree().process_frame
	var zip_path := _staging.path_join("pkg.zip")

	var expected_size := int(_info.get("size", 0))
	if expected_size > 0:
		var f := FileAccess.open(zip_path, FileAccess.READ)
		var actual := f.get_length() if f else -1
		if f:
			f.close()
		if actual != expected_size:
			_fail("download is incomplete (%d of %d bytes)" % [actual, expected_size])
			return
	var expected_sha := String(_info.get("sha256", ""))
	if not expected_sha.is_empty() and FileAccess.get_sha256(zip_path) != expected_sha.to_lower():
		_fail("download is corrupted (checksum mismatch)")
		return

	var extract_dir := _staging.path_join("extract")
	var reason := extract_zip(zip_path, extract_dir)
	if not reason.is_empty():
		_fail(reason)
		return
	DirAccess.remove_absolute(zip_path)
	_payload = find_payload(extract_dir, _target["kind"])
	if _payload.is_empty():
		_fail("the downloaded archive has no game for this platform")
		return
	restore_exec_bits(_payload, _target["kind"])
	ready_to_restart.emit()


func _fail(reason: String) -> void:
	push_warning("[UpdateInstaller] " + reason)
	_reset()
	failed.emit(reason)


func _reset() -> void:
	set_process(false)
	busy = false
	if _http:
		_http.queue_free()
		_http = null
	if not _staging.is_empty():
		remove_recursive(_staging)
