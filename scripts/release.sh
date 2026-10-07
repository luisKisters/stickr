#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
DERIVED="$ROOT/DerivedData-Release"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/Stickr.app"
DMG="$DIST/Stickr.dmg"
IDENTITY="Developer ID Application: Luis William Kisters (4C8444267Z)"
PROFILE="stickr-notary"

cd "$ROOT"
mkdir -p "$DIST"
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Stickr.xcodeproj -scheme Stickr -configuration Release \
  -derivedDataPath "$DERIVED" -jobs 2 ARCHS=arm64 \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=4C8444267Z \
  CODE_SIGN_IDENTITY="$IDENTITY" ENABLE_HARDENED_RUNTIME=YES build

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -e "$DMG" ]]; then mv "$DMG" "$DIST/Stickr.previous.dmg"; fi

if command -v create-dmg >/dev/null; then
  create-dmg --volname "Stickr" --window-pos 180 120 --window-size 660 400 \
    --icon-size 128 --icon "Stickr.app" 170 190 --hide-extension "Stickr.app" \
    --app-drop-link 490 190 --no-internet-enable "$DMG" "$APP"
else
  STAGE=$(mktemp -d /tmp/stickr-dmg.XXXXXX)
  ditto "$APP" "$STAGE/Stickr.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Stickr -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
NOTARY_RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json)
echo "$NOTARY_RESULT"
if [[ $(echo "$NOTARY_RESULT" | jq -r '.status') != Accepted ]]; then exit 1; fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "$DMG"
