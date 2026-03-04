#!/bin/bash
# Sync the version from project.godot into export_presets.cfg.
# Called from the pre-commit hook when project.godot version changes.

set -euo pipefail

PRESETS="export_presets.cfg"

if [ ! -f "$PRESETS" ]; then
	echo "[sync-version] export_presets.cfg not found, skipping."
	exit 0
fi

# Extract version from project.godot (e.g. "0.2.0-release" or "0.2.0")
FULL_VERSION=$(sed -n 's/^config\/version="\([^"]*\)"/\1/p' project.godot)
# Strip suffix like "-release" for short_version
SHORT_VERSION=$(echo "$FULL_VERSION" | sed 's/-.*//')

echo "[sync-version] Syncing version: short=$SHORT_VERSION full=$FULL_VERSION"

# Update iOS / macOS: application/short_version and application/version
sed -i '' -E "s|^(application/short_version=).*|\1\"$SHORT_VERSION\"|" "$PRESETS"
sed -i '' -E "s|^(application/version=).*|\1\"$FULL_VERSION\"|" "$PRESETS"

# Update Android: version/name
sed -i '' -E "s|^(version/name=).*|\1\"$SHORT_VERSION\"|" "$PRESETS"

echo "[sync-version] Updated $PRESETS"
