#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-1.0.0}"
BUILD_NUM="${2:-$(date +%Y%m%d%H%M)}"
APP_NAME="DeepTide.app"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
WEB_DIR="$RES_DIR/Web"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --show-sdk-path)"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$WEB_DIR"
mkdir -p "$ROOT_DIR/.build/module-cache"

export SWIFT_MODULECACHE_PATH="$ROOT_DIR/.build/module-cache"
swiftc DeepTideApp.swift \
  -o "$MACOS_DIR/DeepTide" \
  -framework Cocoa \
  -framework WebKit \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx15.0

cp Info.plist "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ROOT_DIR/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi

cp deeptide.html "$WEB_DIR/deeptide.html"
if [[ -d "$ROOT_DIR/audio" ]]; then
  cp -R "$ROOT_DIR/audio" "$WEB_DIR/audio"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "Built app bundle: $APP_DIR"
echo "Version: $VERSION ($BUILD_NUM)"
