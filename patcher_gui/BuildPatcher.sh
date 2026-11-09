#!/bin/bash
# ==============================================================================
# BuildPatcher.sh - Compile & Package Ninboy Hat Native Port Builder & Patcher GUI
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Ninboy Hat Patcher"
OUTPUT_DIR="${1:-$HOME/Documents/Switch 2 Games}"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

echo "==> [1/4] Compiling Native Swift GUI App..."
TMP_BIN="$(mktemp -d)/NinboyHatPatcher"
swiftc -parse-as-library \
       -target arm64-apple-macos14.0 \
       -O \
       -swift-version 5 \
       -framework AppKit \
       -framework SwiftUI \
       -framework UniformTypeIdentifiers \
       "$SCRIPT_DIR/NinboyHatPatcher.swift" \
       -o "$TMP_BIN"

echo "==> [2/4] Constructing macOS App Bundle ($APP_BUNDLE)..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$TMP_BIN" "$APP_BUNDLE/Contents/MacOS/NinboyHatPatcher"
chmod +x "$APP_BUNDLE/Contents/MacOS/NinboyHatPatcher"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy AppIcon if available
if [ -f "$HOME/Documents/Switch 2 Games/Ocarina of Time.app/Contents/Resources/AppIcon.icns" ]; then
    cp "$HOME/Documents/Switch 2 Games/Ocarina of Time.app/Contents/Resources/AppIcon.icns" \
       "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> [3/4] Signing App Bundle (ad-hoc)..."
codesign -f -s - "$APP_BUNDLE"

echo "==> [4/4] Verifying Installation..."
codesign -v "$APP_BUNDLE"
echo "==> Success! $APP_BUNDLE is ready to launch."
