#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(date +%Y.%m.%d)-$(git rev-parse --short HEAD)}"
BUILD_NUM="${2:-$(date +%Y%m%d%H%M)}"
RELEASE_DIR="$ROOT_DIR/dist/release"
ZIP_PATH="$RELEASE_DIR/DeepTide.app.zip"
PACKAGE_DIR="$RELEASE_DIR/DeepTide-Package"

./scripts/build-app-bundle.sh "$VERSION" "$BUILD_NUM"

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

cp -R "$ROOT_DIR/dist/DeepTide.app" "$PACKAGE_DIR/DeepTide.app"

cat > "$PACKAGE_DIR/START_HERE_INSTALLATION.txt" <<EOF
DeepTide - Schnellstart (macOS)
================================

1) DeepTide.app in den Programme-Ordner ziehen.
2) Beim ersten Start ggf. Rechtsklick auf DeepTide.app -> "Öffnen" -> erneut "Öffnen".
3) Falls blockiert: Systemeinstellungen -> Datenschutz & Sicherheit -> "Dennoch öffnen".
4) In DeepTide die Berechtigungen erlauben (Bedienungshilfen/Automation).
5) In der Kurzbefehle-App zwei Shortcuts erstellen:
   - FocusOn  (Fokus "Nicht stören" EIN)
   - FocusOff (Fokus "Nicht stören" AUS)

Update:
- In DeepTide unten links auf "↻" klicken oder Cmd+U drücken.

Version: $VERSION ($BUILD_NUM)
EOF

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

cat > "$RELEASE_DIR/release-notes.txt" <<EOF
DeepTide release $VERSION ($BUILD_NUM)

Install:
1. Download DeepTide.app.zip
2. Unzip and open the included START_HERE_INSTALLATION.txt
3. Move DeepTide.app to /Applications
4. Open DeepTide and grant Accessibility + Automation permissions
EOF

echo "Release artifact ready:"
echo "  $ZIP_PATH"
echo "  $ZIP_PATH.sha256"
