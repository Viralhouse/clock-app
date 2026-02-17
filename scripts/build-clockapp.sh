#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --show-sdk-path)"
fi

mkdir -p .build/module-cache
export SWIFT_MODULECACHE_PATH="$ROOT_DIR/.build/module-cache"

swiftc ClockApp.swift \
  -o /tmp/ClockApp \
  -framework Cocoa \
  -framework WebKit \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx15.0

echo "Build OK: /tmp/ClockApp"
