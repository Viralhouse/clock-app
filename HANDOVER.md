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
