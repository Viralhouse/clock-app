# Handover: Clock App (Status 2026-02-17)

## Current Product State
- Focus timer UI + quote rotation + rain ambience + 10-track LoFi playlist are implemented.
- Focus toggle works via **Shortcuts CLI first**:
  - `shortcuts run FocusOn`
  - `shortcuts run FocusOff`
- AppleScript UI automation remains as fallback if shortcuts fail.
- App now loads bundled web assets from:
  - `Clock.app/Contents/Resources/Web/clock.html`
  - `Clock.app/Contents/Resources/Web/audio/lofi/*`
- In-app update button (`↻`, top-left) is implemented and wired to GitHub latest release download/install.

## Critical Requirements on Target Mac
1. macOS permissions:
   - Privacy & Security -> Accessibility -> `Clock` enabled
   - Privacy & Security -> Automation -> `Clock` -> `System Events` enabled
2. Required shortcuts must exist:
   - `FocusOn` = Set Focus -> Do Not Disturb -> On
   - `FocusOff` = Set Focus -> Do Not Disturb -> Off
3. App shows a startup popup if those shortcuts are missing.

## Packaging and Distribution
- Build portable app bundle:
  - `./scripts/build-app-bundle.sh <version> [build_num]`
- Build shareable zip:
  - `./scripts/make-release.sh <version> [build_num]`
  - Output: `dist/release/Clock.app.zip`
- Publish GitHub release:
  - `./scripts/publish-release.sh <version> [build_num]`
- Local install helper:
  - `./scripts/install-clock.sh`
- CLI update fallback:
  - `./scripts/update-clock.sh`

## In-App Update Notes
- In-app updater expects `Clock.app.zip` asset in latest GitHub release.
- Repo is currently private; without token, API may return 404.
- Easiest setup: public releases (or token-in-environment strategy).

## Files Added/Changed for Distribution
- `scripts/build-app-bundle.sh`
- `scripts/make-release.sh`
- `scripts/publish-release.sh`
- `scripts/install-clock.sh`
- `scripts/update-clock.sh`
- `DISTRIBUTION.md`
- `ClockApp.swift` (bundle loading, shortcut checks, updater backend)
- `clock.html` (update button + existing timer/audio features)
- `Info.plist` (`ClockUpdateRepo`, version fields)

## Verified Locally
- Friend-like install simulation from `Clock.app.zip` to `/Applications/Clock.app`
- App runs with bundled assets even if local project `clock.html`/`audio` are temporarily removed.
- Debug log confirms bundled path load:
  - `/Applications/Clock.app/Contents/Resources/Web/clock.html`
