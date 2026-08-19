#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/output"
APP_PATH="$PROJECT_DIR/build/macos/Build/Products/Release/plane_chat.app"
DMG_PATH="$OUTPUT_DIR/PlaneChat.dmg"

cd "$PROJECT_DIR"

echo "==> Flutter pub get..."
flutter pub get

echo "==> Building macOS release..."
flutter build macos --release

echo "==> Creating DMG..."
mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"
hdiutil create -volname "PlaneChat" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "==> Done: $DMG_PATH"
ls -lh "$DMG_PATH"
