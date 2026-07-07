#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift run AutoInputSwitcherCoreChecks

"$ROOT_DIR/Scripts/package-release.sh" >/tmp/autoinputswitcher-package.log

test -s "$ROOT_DIR/.build/dist/AutoInputSwitcher-macOS.zip"
test -s "$ROOT_DIR/.build/dist/AutoInputSwitcher-macOS.dmg"
hdiutil imageinfo "$ROOT_DIR/.build/dist/AutoInputSwitcher-macOS.dmg" >/dev/null
