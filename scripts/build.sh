#!/bin/bash
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
