#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-$ROOT_DIR/dist/Clock.app}"
TARGET_APP="/Applications/Clock.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Source app not found: $SOURCE_APP" >&2
  echo "Build first: ./scripts/build-app-bundle.sh" >&2
  exit 1
fi

echo "Installing $SOURCE_APP -> $TARGET_APP"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP" >/dev/null
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "Installed: $TARGET_APP"
echo "Open it once, then allow:"
echo "1) Privacy & Security -> Accessibility -> Clock"
echo "2) Privacy & Security -> Automation -> Clock -> System Events"
