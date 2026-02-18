# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
DeepTide — a macOS deep work timer app with a native Swift host (`Cocoa` + `WebKit`) and a web-based UI. Features: countdown timer, rain/ocean/LoFi ambient sound, Do Not Disturb toggle (via Shortcuts CLI + AppleScript fallback), motivational quotes, dark/light theme, color themes, circular sound visualizer, LoFi playlist (17 bundled MP3s), volume control, and in-app updates from GitHub Releases.

## Architecture
- **`DeepTideApp.swift`** — Native host. Contains `AppDelegate` (window setup, menu, onboarding, shortcut checks), `FocusMessageHandler` (WKScriptMessageHandler bridge for start/stop/update actions, DND toggle logic), and `AppUpdater` (GitHub release download + install).
- **`deeptide.html`** — Single-file web UI loaded in WKWebView. All timer logic, audio (Web Audio API rain/ocean synthesis + `<audio>` LoFi playback), quote rotation, theme switching, visualizer, and playlist controls live here.
- **`Info.plist`** — Bundle metadata. Contains `NSAppleEventsUsageDescription` for System Events access and `DeepTideUpdateRepo` for the GitHub repo path.
- **`audio/lofi/`** — 17 MP3 tracks bundled into `DeepTide.app/Contents/Resources/Web/audio/lofi/`.
- **`scripts/`** — Build and distribution scripts.

Communication: JS calls `window.webkit.messageHandlers.focus.postMessage({action: "start"|"stop"|"update"})`. Swift calls back via `webView.evaluateJavaScript()`.

## Build & Run

```bash
# Build binary
swiftc DeepTideApp.swift -o /tmp/DeepTideApp -framework Cocoa -framework WebKit

# Run directly (uses fallback path ~/claudetest.md/deeptide.html)
/tmp/DeepTideApp

# Build full app bundle with bundled assets
./scripts/build-app-bundle.sh 1.0.0

# Install to ~/Applications
./scripts/install-clock.sh

# Create release zip
./scripts/make-release.sh 1.0.0

# Publish GitHub release (requires gh CLI)
./scripts/publish-release.sh 1.0.0
```

After copying binary into an existing app bundle, re-sign:
```bash
codesign --force --deep --sign - /path/to/DeepTide.app
```

## Key Implementation Details
- `FocusMessageHandler` must be retained as a `var` on `AppDelegate` — WKUserContentController only holds a weak reference.
- DND toggle tries `shortcuts run FocusOn`/`FocusOff` first (6s timeout), falls back to AppleScript UI scripting of Control Center.
- AppleScript targets German macOS: menu bar item found by `description` ("Fokus"/"Focus"), window name "Kontrollzentrum"/"Control Center".
- Rain sound uses 3 layers: brown noise (gain index 3), patter (gain index 8), sporadic drops. LFO modulates main gain.
- Ocean sound uses 3 layers: deep rumble, surf wash with wave LFO, foam hiss.
- The app loads web assets from `Bundle.main/Web/deeptide.html` first, falling back to `~/claudetest.md/deeptide.html` for development.

## macOS Permissions Required
- Privacy & Security → Accessibility → DeepTide
- Privacy & Security → Automation → DeepTide → System Events
- Shortcuts app must have `FocusOn` and `FocusOff` shortcuts configured

## Language
User-facing strings are in German. Code comments and variable names are in English.
