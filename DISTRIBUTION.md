# Clock Distribution and Updates

## 1. Build a Portable App
Run:

```bash
./scripts/build-app-bundle.sh 1.0.0
```

This creates `dist/Clock.app` with bundled web assets:
- `clock.html`
- `audio/lofi/*`

## 2. Local Install (Your Mac)

```bash
./scripts/install-clock.sh
```

## 3. Create Release Artifact for Friends

```bash
./scripts/make-release.sh 1.0.0
```

This creates:
- `dist/release/Clock.app.zip`
- `dist/release/Clock.app.zip.sha256`

Upload `Clock.app.zip` to a GitHub Release in `Viralhouse/clock-app`.

Optional automated publish with GitHub CLI:

```bash
./scripts/publish-release.sh 1.0.0
```

## 4. Friend Install
1. Download `Clock.app.zip` from GitHub Release
2. Unzip and move `Clock.app` to `/Applications`
3. Open app and grant:
   - Privacy & Security -> Accessibility -> `Clock`
   - Privacy & Security -> Automation -> `Clock` -> `System Events`
4. Ensure Shortcuts app has:
   - `FocusOn`
   - `FocusOff`

### Create required shortcuts (once per Mac)
Open the Shortcuts app and create exactly these two shortcuts:

1. `FocusOn`
- Action: `Set Focus`
- Focus mode: `Do Not Disturb`
- State: `On`

2. `FocusOff`
- Action: `Set Focus`
- Focus mode: `Do Not Disturb`
- State: `Off`

Quick verification in Terminal:

```bash
shortcuts list | rg "FocusOn|FocusOff"
shortcuts run FocusOn
shortcuts run FocusOff
```

## 5. Update from GitHub

In-app:
- Click the update button (`↻`) in the top-left corner of the app.
- App downloads latest `Clock.app.zip`, installs, and restarts.

Terminal fallback:

```bash
REPO=Viralhouse/clock-app ./scripts/update-clock.sh
```

If no release exists yet, updater returns `404` (expected).

For private repos, set token first:

```bash
export GITHUB_TOKEN=...
REPO=Viralhouse/clock-app ./scripts/update-clock.sh
```

## Notes
- Current signing is ad-hoc (`codesign -s -`). For best install UX on other Macs, move to a Developer ID certificate + notarization.
- Any re-sign/reinstall can require re-checking macOS permissions.
- In-app updates require a reachable GitHub Releases endpoint. If the repo is private, the app needs `GITHUB_TOKEN` in environment; easiest path is publishing releases publicly.
