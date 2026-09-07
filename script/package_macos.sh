#!/bin/bash
# Build, export, notarize and verify a universal Developer ID DMG.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
UNSIGNED=false
if [[ "${1:-}" == '--unsigned' ]]; then
  UNSIGNED=true
  shift
fi
if [[ "$UNSIGNED" == false ]]; then
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your saved notarytool keychain profile}"
  IDENTITIES=$(security find-identity -v -p codesigning)
  if [[ "$IDENTITIES" != *'Developer ID Application:'* ]]; then
    echo 'Missing Developer ID Application certificate and private key' >&2
    exit 1
  fi
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
fi
[[ "${1:-}" == '--check' ]] && exit 0
VERSION="${1:?Usage: package_macos.sh VERSION BUILD | --check}"
BUILD="${2:?Missing build number}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || exit 2
OUT="$PWD/dist/$VERSION"
mkdir -p "$OUT"
# Fresh staging prevents a stale app or archive from reaching the release.
WORK=$(mktemp -d "$OUT/package.XXXXXX")
cat > "$WORK/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>BPP589VP97</string>
<key>signingStyle</key><string>automatic</string>
<key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
if [[ "$UNSIGNED" == true ]]; then
  xcodebuild -project SealNote.xcodeproj -scheme SealNoteMac -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$PWD/build/ReleaseValidation" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
  mkdir "$WORK/export"
  ditto "$PWD/build/ReleaseValidation/Build/Products/Release/Seal Note.app" "$WORK/export/Seal Note.app"
else
xcodebuild -project SealNote.xcodeproj -scheme SealNoteMac -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$WORK/SealNote.xcarchive" \
  -allowProvisioningUpdates ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
xcodebuild -exportArchive -archivePath "$WORK/SealNote.xcarchive" \
  -exportPath "$WORK/export" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -allowProvisioningUpdates
fi
APP="$WORK/export/Seal Note.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD" ]]
ARCHITECTURES="$(xcrun lipo -archs "$APP/Contents/MacOS/Seal Note")"
[[ " $ARCHITECTURES " == *' arm64 '* && " $ARCHITECTURES " == *' x86_64 '* ]]
if [[ "$UNSIGNED" == false ]]; then
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -q 'Authority=Developer ID Application:'
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
fi
mkdir "$WORK/staging"
ditto "$APP" "$WORK/staging/Seal Note.app"
ln -s /Applications "$WORK/staging/Applications"
DMG="$OUT/Seal-Note-$VERSION.dmg"
hdiutil create -volname 'Seal Note' -srcfolder "$WORK/staging" -ov -format UDZO "$DMG"
if [[ "$UNSIGNED" == false ]]; then
SIGN_ID=$(printf '%s\n' "$IDENTITIES" | sed -n '/Developer ID Application:/s/.*"\(.*\)"/\1/p' | head -1)
codesign --sign "$SIGN_ID" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
hdiutil verify "$DMG"
(cd "$OUT" && shasum -a 256 "Seal-Note-$VERSION.dmg" > SHA256SUMS.txt)
echo "Ready: $DMG"
