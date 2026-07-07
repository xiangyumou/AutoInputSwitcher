#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AutoInputSwitcher"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/.build/dist"
DMG_ROOT="$ROOT_DIR/.build/dmg-root"
DMG_PATH="$DIST_DIR/${APP_NAME}-macOS.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "$APP_PATH does not exist. Run Scripts/build-app.sh first." >&2
    exit 1
fi

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

ditto "$APP_PATH" "$DMG_ROOT/${APP_NAME}.app"
ln -s /Applications "$DMG_ROOT/Applications"
xattr -cr "$DMG_ROOT/${APP_NAME}.app" 2>/dev/null || true

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "Created $DMG_PATH"
