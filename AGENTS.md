# Repository Guidelines

## Project Structure & Module Organization
This repository is DeepTide, a macOS deep work timer app with a web UI.

- `DeepTideApp.swift`: Native macOS host app (`Cocoa` + `WebKit`) and JS bridge for focus/DND actions.
- `deeptide.html`: Frontend timer UI, audio logic, visualizer, and interaction code loaded by the Swift app.
- `Info.plist`: App metadata and runtime permissions for the bundled app.
- `HANDOVER.md`: Operational notes and troubleshooting context.

Keep app logic in `DeepTideApp.swift` and UI/audio behavior in `deeptide.html`.

## Build, Test, and Development Commands
- Build native app binary:
  ```bash
  swiftc DeepTideApp.swift -o /tmp/DeepTideApp -framework Cocoa -framework WebKit
  ```
- Run binary directly for local verification:
  ```bash
  /tmp/DeepTideApp
  ```
- Re-sign app bundle after binary or plist changes:
  ```bash
  codesign --force --deep --sign - /path/to/DeepTide.app
  ```

## Coding Style & Naming Conventions
- Swift: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for vars/functions.
- HTML/JS: keep DOM IDs and message actions explicit and stable (e.g., `"start"`, `"stop"`).
- Prefer small, focused methods and early `guard` returns in Swift bridge/message handlers.
- Keep comments brief and practical, only where behavior is non-obvious (AppleScript/UI scripting).

## Testing Guidelines
There is no automated test suite yet. Use manual validation for each change:

1. Launch the app and verify `deeptide.html` loads.
2. Start timer and confirm focus/DND enable flow.
3. Stop timer and confirm focus/DND disable flow.
4. Validate audio controls and timer behavior in UI.

If adding tests later, place Swift tests under `Tests/` and name files `*Tests.swift`.

## Commit & Pull Request Guidelines
- Commit format: `type(scope): short summary` (e.g., `fix(dnd): handle missing focus menu item`).
- Keep commits small and single-purpose.
- PRs should include: problem statement, change summary, manual test steps, and screenshots/GIFs for UI changes.
- Link related issues/tasks and note any macOS permission or signing prerequisites.
