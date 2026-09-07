#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Seal Note"
VOLUME_NAME="Seal Note"
BUILD_ROOT="$ROOT_DIR/.build"
STAGED_APP="$BUILD_ROOT/dmg-stage/$APP_NAME.app"
SOURCE_APP="${APP_PATH:-}"
VERSION="${VERSION:-}"

mkdir -p "$BUILD_ROOT/dmg-tools" "$BUILD_ROOT/dmg-art" "$BUILD_ROOT/dmg-stage" dist

if [[ -z "$SOURCE_APP" ]]; then
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}" \
    xcodebuild \
      -project SealNote.xcodeproj \
      -scheme SealNoteMac \
      -configuration Release \
      -destination 'platform=macOS' \
      -derivedDataPath "$BUILD_ROOT/DerivedData-DMG" \
      build | tee "$BUILD_ROOT/dmg-release.log"
  SOURCE_APP="$BUILD_ROOT/DerivedData-DMG/Build/Products/Release/$APP_NAME.app"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "App bundle not found: $SOURCE_APP" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
fi
OUTPUT_DMG="${OUTPUT_DMG:-$ROOT_DIR/dist/Seal-Note-$VERSION.dmg}"

# Validate before copying so a signed/notarized export is never silently modified.
# The release script opts out only for its explicitly unsigned prerelease mode.
if [[ "${VERIFY_APP_SIGNATURE:-YES}" == "YES" ]]; then
  codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"
fi
rm -rf "$STAGED_APP"
ditto "$SOURCE_APP" "$STAGED_APP"
if [[ "${VERIFY_APP_SIGNATURE:-YES}" == "YES" ]]; then
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
fi

if [[ ! -f "$BUILD_ROOT/dmg-tools/dmgbuild/__init__.py" ]]; then
  python3 -m pip install --target "$BUILD_ROOT/dmg-tools" dmgbuild numpy Pillow \
    > "$BUILD_ROOT/dmg-deps.log" 2>&1
fi
export PYTHONPATH="$BUILD_ROOT/dmg-tools"
python3 script/make_dmg_art.py

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
ICON_NAME="${ICON_NAME%.icns}"
if [[ -z "$ICON_NAME" || ! -f "$STAGED_APP/Contents/Resources/$ICON_NAME.icns" ]]; then
  echo "Could not find the app's compiled .icns volume icon" >&2
  exit 1
fi
cp "$STAGED_APP/Contents/Resources/$ICON_NAME.icns" "$BUILD_ROOT/dmg-art/SealNote.icns"
tiffutil -cathidpicheck \
  "$BUILD_ROOT/dmg-art/background-1x.png" \
  "$BUILD_ROOT/dmg-art/background.png" \
  -out "$BUILD_ROOT/dmg-art/background.tiff"

rm -f "$OUTPUT_DMG"
python3 -m dmgbuild -s script/dmg_settings.py "$VOLUME_NAME" "$OUTPUT_DMG"
hdiutil verify "$OUTPUT_DMG"
echo "$OUTPUT_DMG"
