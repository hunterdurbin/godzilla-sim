extends Node
## Autoload singleton: checks GitHub Releases for available updates on startup.

## `update` = pending_update (see below).
signal update_available(update: Dictionary)

const GITHUB_API_URL := "https://api.github.com/repos/hunterdurbin/godzilla-sim/releases"

## {current, same_channel: offer, stable_switch: offer} — each offer is
## {tag, download_url, release_url, size, sha256, switch_channel} or {}.
## stable_switch is only ever set for unstable builds.
var pending_update: Dictionary = {}
var later_dismissed: bool = false

var _http: HTTPRequest
var _current_version: String = ""
var _has_checked: bool = false


func _ready() -> void:
	_current_version = ProjectSettings.get_setting("application/config/version", "unknown")
	UpdateInstaller.cleanup_leftovers()
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
	var offers := find_offers(releases, _current_version)
	if offers.is_empty():
		print("[UpdateChecker] No update available")
		return

	print("[UpdateChecker] Update available from %s: same_channel=%s stable_switch=%s" % [
		_current_version, offers["same_channel"].get("tag", "-"), offers["stable_switch"].get("tag", "-")])
	pending_update = offers
	pending_update["current"] = _current_version
	update_available.emit(pending_update)


## Tags of every offer in `update`, comma-joined — the "Skip This Version"
## key. A lone same-channel offer yields just its tag, so skips recorded
## before stable-switch offers existed still match.
static func skip_key(update: Dictionary) -> String:
	var tags: PackedStringArray = []
	for key in ["same_channel", "stable_switch"]:
		var offer: Dictionary = update.get(key, {})
		if not offer.is_empty():
			tags.append(offer["tag"])
	return ",".join(tags)


## Desktop zip builds of both channels share one user:// dir (same
## config/name, no custom user dir), so switching keeps decks/settings/saves.
## Flatpak and mobile channels are separate app ids with separate sandboxes.
static func channel_switch_keeps_data(os_name: String = OS.get_name(), is_flatpak: bool = FileAccess.file_exists("/.flatpak-info")) -> bool:
	return os_name in ["Windows", "macOS", "Linux"] and not is_flatpak


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

## Offers for a build at `current_version`, or {} when there are none.
## - same_channel: the newest newer release on the build's own channel
##   (unstable follows unstable across series; release follows release and
##   release-hotfix).
## - stable_switch (unstable builds only): the newest stable release whose
##   major.minor.patch is at least the build's own — the series it was
##   working toward, or later. Never an older series (a downgrade).
## Releases without an asset for this platform are ignored.
static func find_offers(releases: Array, current_version: String, os_name: String = OS.get_name(), is_flatpak: bool = FileAccess.file_exists("/.flatpak-info")) -> Dictionary:
	var current := parse_version(current_version)
	if current.is_empty():
		return {}

	var same: Dictionary = {}
	var stable: Dictionary = {}
	for release in releases:
		if release.get("draft", false):
			continue
		var candidate := parse_version(release.get("tag_name", ""))
		if candidate.is_empty():
			continue
		var asset := _get_platform_asset(release, os_name, is_flatpak)
		if asset.is_empty():
			continue
		var entry := {"version": candidate, "release": release, "asset": asset}
		if candidate["channel"] == current["channel"]:
			if _is_newer(candidate, current) and (same.is_empty() or _is_newer(candidate, same["version"])):
				same = entry
		elif current["channel"] == "unstable" and candidate["channel"] == "release":
			if _semver_at_least(candidate, current) and (stable.is_empty() or _is_newer(candidate, stable["version"])):
				stable = entry

	if same.is_empty() and stable.is_empty():
		return {}
	return {
		"same_channel": _offer(same, false),
		"stable_switch": _offer(stable, true),
	}


static func _semver_at_least(candidate: Dictionary, current: Dictionary) -> bool:
	for part in ["major", "minor", "patch"]:
		if candidate[part] != current[part]:
			return candidate[part] > current[part]
	return true


static func _offer(entry: Dictionary, switch_channel: bool) -> Dictionary:
	if entry.is_empty():
		return {}
	var asset: Dictionary = entry["asset"]
	return {
		"tag": "v" + entry["version"]["raw"],
		"download_url": asset["url"],
		"release_url": entry["release"].get("html_url", ""),
		"size": asset["size"],
		"sha256": asset["sha256"],
		"switch_channel": switch_channel,
	}


# -- Platform detection -------------------------------------------------------

## The release asset for this platform as {url, size, sha256}; {} if absent.
## `sha256` comes from GitHub's `digest` field ("sha256:<hex>") and is ""
## when the API doesn't provide one.
static func _get_platform_asset(release: Dictionary, os_name: String = OS.get_name(), is_flatpak: bool = FileAccess.file_exists("/.flatpak-info")) -> Dictionary:
	var target_asset := ""

	match os_name:
		"Windows":
			target_asset = "godzilla_tcg_sim-windows.zip"
		"macOS":
			target_asset = "godzilla_tcg_sim-macos.zip"
		"Linux":
			if is_flatpak:
				target_asset = "godzilla_tcg_sim.flatpak"
			else:
				target_asset = "godzilla_tcg_sim-linux.zip"
		"Android":
			# The APK name carries the channel (godzilla_tcg_sim[_unstable].apk);
			# each release ships exactly one.
			target_asset = "*.apk"
		_:
			return {}

	var assets: Array = release.get("assets", [])
	for asset in assets:
		if not String(asset.get("name", "")).match(target_asset):
			continue
		var url: String = asset.get("browser_download_url", "")
		if url.is_empty():
			return {}
		var digest: String = asset.get("digest", "") if asset.get("digest") is String else ""
		return {
			"url": url,
			"size": int(asset.get("size", 0)),
			"sha256": digest.trim_prefix("sha256:") if digest.begins_with("sha256:") else "",
		}

	return {}
