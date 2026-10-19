#!/bin/bash
# Blipp, a menu bar sidekick that shows how your Mac is doing.
# Copyright (C) 2026  Anton Gedda
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Builds Blipp.app into ./build without Xcode (Command Line Tools are enough).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Blipp.app"

echo "→ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --arch arm64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Blipp" "$APP/Contents/MacOS/Blipp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Rendering app icon…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN_DIR/Blipp" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "→ Signing (ad hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Done: $APP"
