#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required: brew install gh" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REPO="${REPO:-Viralhouse/clock-app}"
VERSION="${1:?Usage: ./scripts/publish-release.sh <version> [build_num]}"
BUILD_NUM="${2:-$(date +%Y%m%d%H%M)}"
TAG="v$VERSION"

./scripts/make-release.sh "$VERSION" "$BUILD_NUM"

ZIP_PATH="$ROOT_DIR/dist/release/Clock.app.zip"
NOTES_PATH="$ROOT_DIR/dist/release/release-notes.txt"

gh release create "$TAG" \
  "$ZIP_PATH" \
  --repo "$REPO" \
  --title "Clock $VERSION" \
  --notes-file "$NOTES_PATH"

echo "Release published: $TAG"
