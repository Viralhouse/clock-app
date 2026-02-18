#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-Viralhouse/clock-app}"
TARGET_APP="${TARGET_APP:-/Applications/DeepTide.app}"
ASSET_NAME="${ASSET_NAME:-DeepTide.app.zip}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

API_URL="https://api.github.com/repos/$REPO/releases/latest"
AUTH_HEADER=""
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
elif [[ -n "${GH_TOKEN:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer $GH_TOKEN"
fi

echo "Checking latest release: $REPO"
JSON_PATH="$TMP_DIR/latest.json"
if [[ -n "$AUTH_HEADER" ]]; then
  curl -fsSL -H "$AUTH_HEADER" "$API_URL" -o "$JSON_PATH"
else
  curl -fsSL "$API_URL" -o "$JSON_PATH"
fi

DOWNLOAD_URL="$(/usr/bin/python3 - "$JSON_PATH" "$ASSET_NAME" <<'PY'
import json, sys
path, asset_name = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
for asset in data.get("assets", []):
    if asset.get("name") == asset_name:
        print(asset.get("browser_download_url", ""))
        break
PY
)"

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "No asset named '$ASSET_NAME' found in latest release." >&2
  exit 1
fi

ZIP_PATH="$TMP_DIR/$ASSET_NAME"
echo "Downloading: $DOWNLOAD_URL"
if [[ -n "$AUTH_HEADER" ]]; then
  curl -fL -H "$AUTH_HEADER" "$DOWNLOAD_URL" -o "$ZIP_PATH"
else
  curl -fL "$DOWNLOAD_URL" -o "$ZIP_PATH"
fi

echo "Unpacking..."
ditto -x -k "$ZIP_PATH" "$TMP_DIR/unpacked"
if [[ ! -d "$TMP_DIR/unpacked/DeepTide.app" ]]; then
  echo "Downloaded archive does not contain DeepTide.app" >&2
  exit 1
fi

echo "Installing update to $TARGET_APP"
rm -rf "$TARGET_APP"
cp -R "$TMP_DIR/unpacked/DeepTide.app" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP" >/dev/null
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "Update complete."
echo "If macOS asks again, re-check Accessibility and Automation permissions."
