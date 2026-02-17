# Handover: Clock App Focus Timer — DND Fix

## Status
Die Rain-Sound-Verbesserungen in `clock.html` sind **fertig und funktionieren**.
Das DND-Feature (Nicht stören) funktioniert **vom Terminal aus**, aber **NICHT aus der .app-Bundle** (Dock).

## Root Cause (gefunden!)
Die App-Bundle `Clock.app` hat keine Berechtigung, Apple Events an "System Events" zu senden.
Fehlermeldung aus `/tmp/clock_debug.log`:
```
NSAppleScriptErrorBriefMessage = "Not authorized to send Apple events to System Events.";
NSAppleScriptErrorNumber = "-1743";
```

Wenn die Binary direkt aus dem Terminal gestartet wird (`/tmp/ClockApp`), erbt sie die Automation-Berechtigung von Terminal.app → funktioniert.
Als eigenständige `.app` braucht sie eine eigene Berechtigung.

## Lösung (muss noch implementiert werden)

### Option A: Info.plist + Entitlements (empfohlen)
1. **`Info.plist`** erweitern um `NSAppleEventsUsageDescription`:
   ```xml
   <key>NSAppleEventsUsageDescription</key>
   <string>Clock benötigt Zugriff auf System Events um "Nicht stören" automatisch zu steuern.</string>
   ```
   Datei: `/Users/vincentjutte/Applications/Clock.app/Contents/Info.plist`

2. Die App muss **code-signed** werden damit macOS den Automation-Dialog anzeigt:
   ```bash
   codesign --force --deep --sign - /Users/vincentjutte/Applications/Clock.app
   ```

3. Beim ersten Start sollte macOS dann einen Dialog anzeigen: "Clock möchte System Events steuern".

### Option B: Manuelle Berechtigung
- Systemeinstellungen → Datenschutz & Sicherheit → Automatisierung
- Clock.app manuell hinzufügen und "System Events" erlauben
- Problem: Die App taucht dort evtl. nicht auf ohne Code-Signierung

### Option C: Shortcuts statt AppleScript (Alternative)
Statt AppleScript könnte man `shortcuts run "FocusOn"` / `shortcuts run "FocusOff"` verwenden.
Das wurde bereits versucht, aber `shortcuts run` hing (blockierte endlos).
Mögliche Lösung: Shortcuts mit Timeout ausführen oder prüfen ob die Shortcuts korrekt konfiguriert sind.

## Dateien

### `/tmp/ClockApp.swift` — Swift-Quellcode
- Message Handler empfängt korrekt JS-Messages (`[String: Any]` statt `[String: String]`)
- `focusHandler` wird als `var` im AppDelegate gehalten (nicht weak reference)
- DND-Logik:
  - **Einschalten**: Kontrollzentrum öffnen → checkbox 2 klicken
  - **Ausschalten**: Fokus-Menüleisten-Item klicken → checkbox 1 klicken
- Enthält aktuell Debug-Logging nach `/tmp/clock_debug.log` (kann entfernt werden)

### `/Users/vincentjutte/claudetest.md/clock.html` — Web-Frontend
- Rain Sound: Fertig und funktioniert
  - Leise (gain 0.15 statt 0.7)
  - LFO-Modulation für Regenwellen
  - Sporadische Tropfen-Sounds
  - Brown noise multiplier 1.5 statt 3.5, bandpass 600Hz statt 800Hz

### `/Users/vincentjutte/Applications/Clock.app/` — App Bundle
- `Contents/MacOS/Clock` — Bash-Wrapper, startet ClockApp
- `Contents/MacOS/ClockApp` — Kompilierte Binary (aktuell mit Debug-Logging)
- `Contents/Info.plist` — Muss um `NSAppleEventsUsageDescription` erweitert werden

## Nächste Schritte
1. `Info.plist` um `NSAppleEventsUsageDescription` erweitern
2. App mit `codesign --force --deep --sign -` signieren
3. Debug-Logging aus `ClockApp.swift` entfernen
4. Neu kompilieren: `swiftc /tmp/ClockApp.swift -o /tmp/ClockApp -framework Cocoa -framework WebKit`
5. Binary kopieren: `cp /tmp/ClockApp "/Users/vincentjutte/Applications/Clock.app/Contents/MacOS/ClockApp"`
6. Code-signieren: `codesign --force --deep --sign - /Users/vincentjutte/Applications/Clock.app`
7. App starten → Automation-Dialog sollte erscheinen → erlauben
8. Timer testen → DND sollte funktionieren

## Build-Befehl
```bash
swiftc /tmp/ClockApp.swift -o /tmp/ClockApp -framework Cocoa -framework WebKit
cp /tmp/ClockApp "/Users/vincentjutte/Applications/Clock.app/Contents/MacOS/ClockApp"
codesign --force --deep --sign - /Users/vincentjutte/Applications/Clock.app
```
---

## Feature Request: Lofi Hip Hop Beats

### Goal
The user wants to extend the clock app to include the option to play lofi hip hop beats in addition to the existing rain sounds.

### Challenge: Finding a Suitable Audio File
My attempt to automatically find and download a copyright-free MP3 file was unsuccessful. The main difficulties were:
-   Search tools are not well-suited for discovering direct download links for audio files.
-   Many websites with free audio use JavaScript-based download buttons that cannot be programmatically triggered.
-   Verifying the license of audio files programmatically is unreliable.

### Next Steps (for the next agent)

The core task is to obtain a direct link to an MP3 file and then integrate it into the `clock.html` page.

**1. Obtain MP3 File from User**
-   You must ask the user to find and provide a **direct URL** to a copyright-free or appropriately licensed MP3 file.
-   Suggest that the user can manually browse sites like `pixabay.com`, `bensound.com`, or `stocktune.com` to find a suitable track.
-   Once the user provides a URL (e.g., `https://example.com/lofi-track.mp3`), you can proceed.

**2. Download the MP3 File**
-   Use a shell command to download the file into the project directory.
-   Example command:
    ```bash
    curl -L -o lofi.mp3 "URL_FROM_USER"
    ```

**3. Integrate into `clock.html`**
-   The `clock.html` file needs to be modified to include an audio player.
-   **HTML Changes**:
    -   Add an `<audio>` element for the lofi track.
    -   Add a button to control playback.
    -   Example:
        ```html
        <!-- Somewhere in the body -->
        <audio id="lofi-audio" src="lofi.mp3" loop></audio>
        <button id="lofi-play-pause">Play Lofi</button>
        ```
-   **JavaScript Changes**:
    -   Add an event listener to the button to toggle play/pause on the `<audio>` element.
    -   Example:
        ```javascript
        const lofiAudio = document.getElementById('lofi-audio');
        const lofiButton = document.getElementById('lofi-play-pause');

        lofiButton.addEventListener('click', () => {
          if (lofiAudio.paused) {
            lofiAudio.play();
            lofiButton.textContent = 'Pause Lofi';
          } else {
            lofiAudio.pause();
            lofiButton.textContent = 'Play Lofi';
          }
        });
        ```
-   This new functionality should be integrated carefully with the existing rain sound logic to ensure they don't conflict (e.g., volume controls, UI placement).

---

## Update 2026-02-17 (Current State)

### Erledigt
- **LoFi-Funktion ist implementiert** in `clock.html`:
  - Sound-Modus-Button hinzugefügt: `Sound: Rain` / `Sound: LoFi`
  - `<audio id="lofiAudio" src="lofi.mp3" loop preload="auto"></audio>`
  - Gemeinsame Ambience-Logik: `startAmbience()` / `stopAmbience()`
  - Fallback auf Rain, falls LoFi nicht abgespielt werden kann
- **`lofi.mp3` wurde heruntergeladen** und liegt im Repo-Root.
- **Toolchain/SDK-Buildproblem gelöst** über Build-Skript:
  - `scripts/build-clockapp.sh`
  - Nutzt lokales Module-Cache-Verzeichnis (`.build/module-cache`)
  - Pinnt auf `MacOSX15.5.sdk` (falls vorhanden), sonst `xcrun --show-sdk-path`
- **Clock.app wurde aktualisiert und neu signiert**:
  - Binary nach `~/Applications/Clock.app/Contents/MacOS/ClockApp` kopiert
  - `codesign --force --deep --sign - ~/Applications/Clock.app`
- **GitHub-Verbindung eingerichtet**:
  - Remote: `git@github.com:Viralhouse/clock-app.git`
  - Repo wurde auf **private** umgestellt.

### Build & Deploy (funktionierender Ablauf)
```bash
cd /Users/vincentjutte/claudetest.md
./scripts/build-clockapp.sh
cp /tmp/ClockApp "/Users/vincentjutte/Applications/Clock.app/Contents/MacOS/ClockApp"
codesign --force --deep --sign - "/Users/vincentjutte/Applications/Clock.app"
```

### Wichtiger Hinweis (offen)
- Die DND-Automation aus der `.app` kann weiterhin an macOS-Automation-Rechten hängen (`System Events`, Fehler `-1743`), falls die Berechtigung nicht angezeigt/erteilt wurde.
- Falls nötig:
  1. `NSAppleEventsUsageDescription` in `Clock.app/Contents/Info.plist` sicherstellen
  2. App erneut signieren
  3. App neu starten und Automation-Dialog erlauben
