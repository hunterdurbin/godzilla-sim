extends Node
## Autoload singleton: checks GitHub Releases for available updates on startup.

signal update_available(current_version: String, new_version: String, download_url: String, release_url: String)

const GITHUB_API_URL := "https://api.github.com/repos/hunterdurbin/godzilla-sim/releases"

var pending_update: Dictionary = {}

var _http: HTTPRequest
var _current_version: String = ""
var _has_checked: bool = false


func _ready() -> void:
	_current_version = ProjectSettings.get_setting("application/config/version", "unknown")
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	check_for_updates.call_deferred()


func check_for_updates() -> void:
	if _has_checked:
		return
	_has_checked = true
	var err := _http.request(GITHUB_API_URL, ["Accept: application/vnd.github+json"])
	if err != OK:
		print("[UpdateChecker] HTTP request failed to start: %d" % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[UpdateChecker] Check failed (result=%d, code=%d)" % [result, response_code])
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("[UpdateChecker] Failed to parse releases JSON")
		return

	var releases: Array = json.data if json.data is Array else []
	var best := _find_best_update(releases)
	if best.is_empty():
		print("[UpdateChecker] No update available")
		return

	var new_tag: String = best["tag"]
	if new_tag == GameSettings.skipped_version:
		print("[UpdateChecker] Update %s was previously skipped" % new_tag)
		return

	print("[UpdateChecker] Update available: %s -> %s" % [_current_version, new_tag])
	pending_update = {
		"current": _current_version,
		"new_version": new_tag,
		"download_url": best["download_url"],
		"release_url": best["release_url"],
	}
	update_available.emit(_current_version, new_tag, best["download_url"], best["release_url"])


# -- Version parsing ----------------------------------------------------------

static func parse_version(tag: String) -> Dictionary:
	var version_str := tag.trim_prefix("v")
	var dash_index := version_str.find("-")
	if dash_index == -1:
		return {}

	var semver_part := version_str.substr(0, dash_index)
	var suffix := version_str.substr(dash_index + 1)

	var parts := semver_part.split(".")
	if parts.size() != 3:
		return {}

	var major := parts[0].to_int()
	var minor := parts[1].to_int()
	var patch := parts[2].to_int()

	var channel := ""
	var number := 0

	if suffix == "release":
		channel = "release"
	elif suffix.begins_with("release-hotfix."):
		channel = "release"
		number = suffix.get_slice(".", 1).to_int()
	elif suffix.begins_with("unstable."):
		channel = "unstable"
		number = suffix.get_slice(".", 1).to_int()
	else:
		return {}

	return {
		"major": major, "minor": minor, "patch": patch,
		"channel": channel, "number": number,
		"raw": version_str,
	}


static func _is_newer(candidate: Dictionary, current: Dictionary) -> bool:
	if candidate["major"] != current["major"]:
		return candidate["major"] > current["major"]
	if candidate["minor"] != current["minor"]:
		return candidate["minor"] > current["minor"]
	if candidate["patch"] != current["patch"]:
		return candidate["patch"] > current["patch"]
	return candidate["number"] > current["number"]


# -- Update detection ---------------------------------------------------------

func _find_best_update(releases: Array) -> Dictionary:
	var current := parse_version(_current_version)
	if current.is_empty():
		return {}

	var best_version: Dictionary = {}
	var best_download_url := ""
	var best_release_url := ""

	for release in releases:
		var tag: String = release.get("tag_name", "")
		var candidate := parse_version(tag)
		if candidate.is_empty():
			continue
		if release.get("draft", false):
			continue

		# Channel filtering
		if current["channel"] == "unstable":
			# Unstable: only update within the SAME semver series
			if candidate["channel"] != "unstable":
				continue
			if candidate["major"] != current["major"] or \
				candidate["minor"] != current["minor"] or \
				candidate["patch"] != current["patch"]:
				continue
			if candidate["number"] <= current["number"]:
				continue
		elif current["channel"] == "release":
			# Release: update to any newer release or release-hotfix
			if candidate["channel"] != "release":
				continue
			if not _is_newer(candidate, current):
				continue

		# Track the best (highest) version found
		if best_version.is_empty() or _is_newer(candidate, best_version):
			best_version = candidate
			best_download_url = _get_platform_asset_url(release)
			best_release_url = release.get("html_url", "")

	if best_version.is_empty() or best_download_url.is_empty():
		return {}

	return {
		"tag": "v" + best_version["raw"],
		"download_url": best_download_url,
		"release_url": best_release_url,
	}


# -- Platform detection -------------------------------------------------------

static func _get_platform_asset_url(release: Dictionary) -> String:
	var os_name := OS.get_name()
	var target_asset := ""

	match os_name:
		"Windows":
			target_asset = "godzilla_tcg_sim-windows.zip"
		"macOS":
			target_asset = "godzilla_tcg_sim-macos.zip"
		"Linux":
			if FileAccess.file_exists("/.flatpak-info"):
				target_asset = "godzilla_tcg_sim.flatpak"
			else:
				target_asset = "godzilla_tcg_sim-linux.zip"
		_:
			return ""

	var assets: Array = release.get("assets", [])
	for asset in assets:
		if asset.get("name", "") == target_asset:
			return asset.get("browser_download_url", "")

	return ""
