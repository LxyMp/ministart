#!/bin/bash
# Package Ministart as build/Ministart-<version>.dmg — the .app stays an intermediate.
# Usage: build-dmg.sh [version]. Falls back to ad-hoc signing without the self-signed identity.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED="build/DerivedData"

if security find-identity -p codesigning | grep -q "Ministart Self-Signed"; then
    IDENTITY="Ministart Self-Signed"
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none")
else
    echo "▸ No self-signed identity — packaging ad-hoc"
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="")
fi

echo "▸ Building Ministart.app (Release)…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    "${SIGNING[@]}" \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/Ministart.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Ministart-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Ministart" "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ $DMG"
