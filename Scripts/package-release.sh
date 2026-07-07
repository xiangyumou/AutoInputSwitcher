#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AutoInputSwitcher"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/dist"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS.zip"

cd "$ROOT_DIR"

CONFIGURATION="$CONFIGURATION" VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    "$ROOT_DIR/Scripts/build-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
xattr -cr "$ROOT_DIR/.build/${APP_NAME}.app" 2>/dev/null || true
(
    cd "$ROOT_DIR/.build"
    /usr/bin/zip -qry "$ZIP_PATH" "${APP_NAME}.app" -x "*.DS_Store"
)

echo "Packaged $ZIP_PATH"
