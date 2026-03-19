#!/usr/bin/env bash
set -uo pipefail

# Local iOS build script for Unofficial Godzilla Sim
# Exports the Godot project to an Xcode project, then opens Xcode for signing and deployment.
#
# Prerequisites:
#   - Xcode (full install, not just Command Line Tools)
#   - Godot 4.6 with iOS export templates installed
#   - Apple Developer Team ID set in export_presets.cfg
#   - Signing certificate in Keychain (Xcode > Settings > Accounts > Manage Certificates)
#
# Usage:
#   ./build_ios.sh                     # Export Xcode project and open it
#   ./build_ios.sh --unstable          # Build the unstable variant (different bundle ID)
#   ./build_ios.sh --no-open           # Export Xcode project without opening
#   GODOT_BIN=/path/to/Godot ./build_ios.sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/ios"
EXPORT_PRESET="iOS"
PROJECT_NAME="godzilla_tcg_sim"
OPEN_XCODE=true
GODOT_BIN="${GODOT_BIN:-godot}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --unstable)
            EXPORT_PRESET="iOS Unstable"
            PROJECT_NAME="godzilla_tcg_sim_unstable"
            shift
            ;;
        --no-open)
            OPEN_XCODE=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Exports the Godot project as an Xcode project for iOS."
            echo "Signing and deployment are handled in Xcode."
            echo ""
            echo "Options:"
            echo "  --unstable      Build the unstable variant (different bundle ID)"
            echo "  --no-open       Don't open Xcode after export"
            echo "  -h, --help      Show this help"
            echo ""
            echo "Environment:"
            echo "  GODOT_BIN       Path to Godot binary (default: godot)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Preflight checks ---

echo "=== iOS Build Script ==="
echo ""

# Check Xcode (full install, not just CLT)
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    echo "ERROR: Full Xcode installation required (not just Command Line Tools)."
    echo "  Install Xcode from the App Store, then run:"
    echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "    sudo xcodebuild -license accept"
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || echo "unknown")
echo "Xcode: ${XCODE_VERSION}"

# Check Godot
if ! command -v "${GODOT_BIN}" &>/dev/null; then
    echo "ERROR: Godot not found at '${GODOT_BIN}'."
    echo "  Either add Godot to your PATH or set GODOT_BIN:"
    echo "    export GODOT_BIN=/path/to/Godot.app/Contents/MacOS/Godot"
    exit 1
fi

GODOT_VERSION=$("${GODOT_BIN}" --version 2>/dev/null | head -1 || echo "unknown")
echo "Godot: ${GODOT_VERSION}"

# Check iOS export templates
TEMPLATES_DIR="${HOME}/Library/Application Support/Godot/export_templates"
if [ ! -d "${TEMPLATES_DIR}" ]; then
    echo "ERROR: No Godot export templates found."
    echo "  Open Godot Editor > Editor > Manage Export Templates > Download"
    exit 1
fi
echo "Export templates: ${TEMPLATES_DIR}"
echo ""

# --- Export from Godot ---

# Clean previous export
if [ -d "${BUILD_DIR}" ]; then
    echo "Cleaning previous build..."
    rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}"

echo "=== Exporting Godot project ==="
echo ""

# Run the export. Godot's iOS --export-debug generates the Xcode project and then
# attempts to archive/sign it via xcodebuild. The archive step often fails (no device
# registered, no provisioning profile, etc.) but the Xcode project is still generated
# successfully. We ignore the exit code and check for the .xcodeproj instead.
"${GODOT_BIN}" --headless --export-debug "${EXPORT_PRESET}" "${BUILD_DIR}/${PROJECT_NAME}.ipa" --path "${PROJECT_DIR}" 2>&1 || true

# Check if the Xcode project was generated (this is what we actually need)
if [ ! -d "${BUILD_DIR}/${PROJECT_NAME}.xcodeproj" ]; then
    echo ""
    echo "ERROR: Xcode project was not generated."
    echo "  Check the Godot output above for errors."
    echo "  You may need to open the project in Godot Editor and export iOS manually"
    echo "  via Project > Export to see detailed error messages."
    exit 1
fi

echo ""
echo "=== Xcode project exported successfully ==="
echo "  ${BUILD_DIR}/${PROJECT_NAME}.xcodeproj"
echo ""

# --- Post-export patches ---
INFOPLIST="${BUILD_DIR}/${PROJECT_NAME}/${PROJECT_NAME}-Info.plist"
SPLASH_DIR="${BUILD_DIR}/${PROJECT_NAME}/Images.xcassets/SplashImage.imageset"
GAME_ICON="${PROJECT_DIR}/assets/icons/game_icon.png"

if [ -f "${INFOPLIST}" ]; then
    echo "Patching orientations..."
    plutil -replace UISupportedInterfaceOrientations -json '["UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight"]' "${INFOPLIST}"
    plutil -replace "UISupportedInterfaceOrientations~ipad" -json '["UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight"]' "${INFOPLIST}"
fi

if [ -d "${SPLASH_DIR}" ] && [ -f "${GAME_ICON}" ]; then
    echo "Replacing launch splash with game icon..."
    cp "${GAME_ICON}" "${SPLASH_DIR}/splash@2x.png"
    cp "${GAME_ICON}" "${SPLASH_DIR}/splash@3x.png"
fi

# Fix Release signing identity for free (Personal Team) Apple ID
PBXPROJ="${BUILD_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"
if [ -f "${PBXPROJ}" ]; then
    echo "Patching Release signing to Apple Development..."
    sed -i '' 's/"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = "iPhone Distribution"/"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Development"/g' "${PBXPROJ}"
    sed -i '' 's/CODE_SIGN_IDENTITY = "iPhone Distribution"/CODE_SIGN_IDENTITY = "Apple Development"/g' "${PBXPROJ}"
    sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Distribution"/CODE_SIGN_IDENTITY = "Apple Development"/g' "${PBXPROJ}"
fi

echo ""

# --- Build unsigned .ipa from command line ---

ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
IPA_PATH="${BUILD_DIR}/${PROJECT_NAME}.ipa"

echo "=== Building archive (unsigned) ==="
xcodebuild \
    -project "${BUILD_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${PROJECT_NAME}" \
    -configuration Release \
    -sdk iphoneos \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    archive

if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo "ERROR: Archive failed. Check the output above."
    exit 1
fi

echo ""
echo "=== Packaging .ipa ==="
PAYLOAD_DIR="${BUILD_DIR}/Payload"
rm -rf "${PAYLOAD_DIR}"
mkdir -p "${PAYLOAD_DIR}"
cp -r "${ARCHIVE_PATH}/Products/Applications/"*.app "${PAYLOAD_DIR}/"
cd "${BUILD_DIR}" && zip -qr "${PROJECT_NAME}.ipa" Payload
rm -rf "${PAYLOAD_DIR}"

if [ -f "${IPA_PATH}" ]; then
    echo ""
    echo "=== Success! ==="
    echo "  .ipa: ${IPA_PATH}"
    echo ""
    echo "Share this .ipa with users. They can install it via AltStore or SideStore."
else
    echo "ERROR: Failed to create .ipa"
    exit 1
fi

if [ "${OPEN_XCODE}" = true ]; then
    open "${BUILD_DIR}"
fi
