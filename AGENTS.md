# Repository Guidelines

## Project Structure & Module Organization
This repository is a lightweight macOS clock/focus app with a web UI.

- `ClockApp.swift`: Native macOS host app (`Cocoa` + `WebKit`) and JS bridge for focus/DND actions.
- `clock.html`: Frontend timer UI, audio logic, and interaction code loaded by the Swift app.
- `Info.plist`: App metadata and runtime permissions for the bundled app.
- `ClockApp`: Compiled binary artifact; treat as build output, not source of truth.
- `HANDOVER.md`: Operational notes and troubleshooting context.

Keep app logic in `ClockApp.swift` and UI/audio behavior in `clock.html`.

## Build, Test, and Development Commands
- Build native app binary:
  ```bash
  swiftc ClockApp.swift -o /tmp/ClockApp -framework Cocoa -framework WebKit
  ```
- Run binary directly for local verification:
  ```bash
  /tmp/ClockApp
  ```
- Update bundled app binary (local machine path):
  ```bash
  cp /tmp/ClockApp "/Users/vincentjutte/Applications/Clock.app/Contents/MacOS/ClockApp"
  ```
- Re-sign app bundle after binary or plist changes:
  ```bash
  codesign --force --deep --sign - /Users/vincentjutte/Applications/Clock.app
  ```

## Coding Style & Naming Conventions
- Swift: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for vars/functions.
- HTML/JS: keep DOM IDs and message actions explicit and stable (e.g., `"start"`, `"stop"`).
- Prefer small, focused methods and early `guard` returns in Swift bridge/message handlers.
- Keep comments brief and practical, only where behavior is non-obvious (AppleScript/UI scripting).

## Testing Guidelines
There is no automated test suite yet. Use manual validation for each change:

1. Launch the app and verify `clock.html` loads.
2. Start timer and confirm focus/DND enable flow.
3. Stop timer and confirm focus/DND disable flow.
4. Validate audio controls and timer behavior in UI.

If adding tests later, place Swift tests under `Tests/` and name files `*Tests.swift`.

## Commit & Pull Request Guidelines
No git history is available in this workspace, so use this default convention:

- Commit format: `type(scope): short summary` (e.g., `fix(dnd): handle missing focus menu item`).
- Keep commits small and single-purpose.
- PRs should include: problem statement, change summary, manual test steps, and screenshots/GIFs for UI changes.
- Link related issues/tasks and note any macOS permission or signing prerequisites.
