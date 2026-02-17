#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(date +%Y.%m.%d)-$(git rev-parse --short HEAD)}"
BUILD_NUM="${2:-$(date +%Y%m%d%H%M)}"
RELEASE_DIR="$ROOT_DIR/dist/release"
ZIP_PATH="$RELEASE_DIR/Clock.app.zip"

./scripts/build-app-bundle.sh "$VERSION" "$BUILD_NUM"

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/Clock.app" "$ZIP_PATH"

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

cat > "$RELEASE_DIR/release-notes.txt" <<EOF
Clock release $VERSION ($BUILD_NUM)

Install:
1. Download Clock.app.zip
2. Unzip and move Clock.app to /Applications
3. Open Clock and grant Accessibility + Automation permissions
EOF

echo "Release artifact ready:"
echo "  $ZIP_PATH"
echo "  $ZIP_PATH.sha256"
