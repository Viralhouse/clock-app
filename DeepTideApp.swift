import Cocoa
import WebKit

class FocusMessageHandler: NSObject, WKScriptMessageHandler {
    private let debugLogPath = "/tmp/deeptide_debug.log"
    private let updateStateQueue = DispatchQueue(label: "deeptide.update.state")
    private var isUpdateInProgress = false
    private let spotifyQueue = DispatchQueue(label: "deeptide.spotify")
    private var spotifyPollTimer: DispatchSourceTimer?
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let payload = message.body as? [String: Any]
        let action: String?
        if let body = payload {
            action = body["action"] as? String
        } else if let body = message.body as? String {
            action = body
        } else {
            action = nil
        }

        guard let action else {
            log("Focus message ignored: unsupported body type: \(type(of: message.body))")
            return
        }
        log("Focus message received: \(action)")

        switch action {
        case "start":
            setDND(enabled: true)
        case "stop":
            setDND(enabled: false)
        case "update":
            performInAppUpdate()
        case "spotifyRefresh":
            refreshSpotifyState()
        case "spotifyPrev":
            runSpotifyCommand("previous track")
        case "spotifyPlayPause":
            runSpotifyCommand("playpause")
        case "spotifyNext":
            runSpotifyCommand("next track")
        case "spotifyPlay":
            runSpotifyCommand("play")
        case "spotifyPause":
            runSpotifyCommand("pause")
        case "spotifyPlayFast":
            runSpotifyCommand("play", refreshState: false)
        case "spotifyPauseFast":
            runSpotifyCommand("pause", refreshState: false)
        case "spotifyFocus":
            runSpotifyFocus()
        case "spotifyToggleLike":
            runSpotifyToggleLike()
        case "spotifySeek":
            if let pos = payload?["position"] as? Double {
                runSpotifySeek(position: pos)
            } else if let pos = payload?["position"] as? NSNumber {
                runSpotifySeek(position: pos.doubleValue)
            }
        case "spotifySetVolume":
            if let vol = payload?["volume"] as? Double {
                runSpotifySetVolume(vol)
            } else if let vol = payload?["volume"] as? NSNumber {
                runSpotifySetVolume(vol.doubleValue)
            }
        default:
            break
        }
    }

    func requestUpdateFromNative() {
        performInAppUpdate()
    }

    func startSpotifyMonitoring() {
        spotifyQueue.async { [weak self] in
            guard let self else { return }
            if self.spotifyPollTimer != nil { return }
            let timer = DispatchSource.makeTimerSource(queue: self.spotifyQueue)
            timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in
                self?.publishSpotifyState()
            }
            self.spotifyPollTimer = timer
            timer.resume()
        }
    }

    private func performInAppUpdate() {
        guard beginUpdateIfPossible() else {
            postUpdateState("already_running", message: "Update is already running...")
            return
        }
        postUpdateState("started", message: "Checking for updates...")
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let updater = AppUpdater(
                log: log,
                status: { [weak self] title, message in
                    if message.contains("Installing update") {
                        self?.postUpdateState("installing", message: message)
                    } else if message.contains("failed") {
                        self?.postUpdateState("error", message: message)
                    } else if message.contains("Already up-to-date") {
                        self?.postUpdateState("finished", message: message)
                    }
                    self?.showUpdateAlert(title: title, message: message)
                },
                progress: { [weak self] message in
                    self?.postUpdateState("progress", message: message)
                }
            )
            updater.run()
            endUpdate()
            postUpdateState("finished", message: "")
        }
    }

    private func beginUpdateIfPossible() -> Bool {
        updateStateQueue.sync {
            if isUpdateInProgress {
                return false
            }
            isUpdateInProgress = true
            return true
        }
    }

    private func endUpdate() {
        updateStateQueue.sync {
            isUpdateInProgress = false
        }
    }

    private func postUpdateState(_ state: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let payload: [String: String] = [
                "state": state,
                "message": message
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let js = "window.handleNativeUpdateState && window.handleNativeUpdateState(\(json));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func showUpdateAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func setDND(enabled: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if runFocusShortcut(enabled: enabled) {
                return
            }
            DispatchQueue.main.async { [self] in
                runAppleScriptDND(enabled: enabled)
            }
        }
    }

    private func refreshSpotifyState() {
        spotifyQueue.async { [weak self] in
            self?.publishSpotifyState()
        }
    }

    private func runSpotifyCommand(_ command: String, refreshState: Bool = true) {
        spotifyQueue.async { [weak self] in
            guard let self else { return }
            let script = """
            if application "Spotify" is running then
                tell application "Spotify"
                    \(command)
                end tell
            end if
            """
            _ = self.runAppleScript(script)
            if refreshState {
                self.publishSpotifyState()
            }
        }
    }

    private func runSpotifySeek(position: Double) {
        spotifyQueue.async { [weak self] in
            guard let self else { return }
            let safePosition = max(0, position)
            let script = """
            if application "Spotify" is running then
                tell application "Spotify"
                    set player position to \(safePosition)
                end tell
            end if
            """
            _ = self.runAppleScript(script)
            self.publishSpotifyState()
        }
    }

    private func runSpotifySetVolume(_ volume: Double) {
        spotifyQueue.async { [weak self] in
            guard let self else { return }
            let clamped = max(0, min(100, Int(volume.rounded())))
            let script = """
            if application "Spotify" is running then
                tell application "Spotify"
                    set sound volume to \(clamped)
                end tell
            end if
            """
            _ = self.runAppleScript(script)
        }
    }

    private func runSpotifyToggleLike() {
        spotifyQueue.async { [weak self] in
            guard let self else { return }
            // Most reliable path: user-defined Shortcuts action for "like current Spotify track".
            var shortcutCandidates = self.detectSpotifyLikeShortcuts()
            shortcutCandidates.append(contentsOf: [
                "SpotifyLikeCurrentTrack",
                "SpotifyLike",
                "LikeCurrentTrack",
                "Spotify Zu Lieblingssongs hinzufügen",
                "Spotify Zu Lieblingssongs",
                "Zu Lieblingssongs hinzufügen"
            ])
            for name in shortcutCandidates {
                if self.runNamedShortcut(name: name, timeout: 5.0) {
                    self.publishSpotifyLikeResult("ok_shortcuts_app")
                    self.publishSpotifyState()
                    return
                }
            }

            let script = """
            tell application "System Events"
                if not (exists process "Spotify") then
                    return "not_running"
                end if

                tell process "Spotify"
                    set frontmost to true
                    delay 0.06

                    set toggled to false

                    -- Strategy 0: direct like button in main content (German/English labels)
                    try
                        set directLikeButton to missing value
                        set allButtons to buttons of entire contents of window 1
                        repeat with b in allButtons
                            try
                                set btnName to ""
                                set btnDesc to ""
                                try
                                    set btnName to (name of b as text)
                                end try
                                try
                                    set btnDesc to (description of b as text)
                                end try

                                if btnName contains "Zu Lieblingssongs hinzufügen" or btnName contains "Aus Lieblingssongs entfernen" or btnName contains "Liked Songs" or btnName contains "Save to your Liked Songs" or btnName contains "Remove from your Liked Songs" then
                                    set directLikeButton to b
                                    exit repeat
                                end if

                                if btnDesc contains "Zu Lieblingssongs hinzufügen" or btnDesc contains "Aus Lieblingssongs entfernen" or btnDesc contains "Liked Songs" or btnDesc contains "Save to your Liked Songs" or btnDesc contains "Remove from your Liked Songs" then
                                    set directLikeButton to b
                                    exit repeat
                                end if
                            end try
                        end repeat

                        if directLikeButton is not missing value then
                            click directLikeButton
                            return "ok_direct_button"
                        end if
                    end try

                    -- Strategy 1: Song/Titel menu item (most reliable across layouts)
                    set songMenuItem to missing value
                    repeat with mbi in menu bar items of menu bar 1
                        try
                            set menuTitle to (name of mbi as text)
                            if menuTitle is "Song" or menuTitle is "Titel" then
                                set songMenuItem to mbi
                                exit repeat
                            end if
                        end try
                    end repeat

                    if songMenuItem is not missing value then
                        click songMenuItem
                        delay 0.08
                        try
                            set targetItem to missing value
                            set menuItemsList to menu items of menu 1 of songMenuItem
                            repeat with mi in menuItemsList
                                try
                                    set itemName to (name of mi as text)
                                    if itemName contains "Zu Lieblingssongs hinzufügen" or itemName contains "Aus Lieblingssongs entfernen" or itemName contains "Liked Songs" or itemName contains "Lieblingssongs" or itemName contains "Save to Your Liked Songs" or itemName contains "Remove from your Liked Songs" then
                                        set targetItem to mi
                                        exit repeat
                                    end if
                                end try
                            end repeat

                            if targetItem is not missing value then
                                click targetItem
                                set toggled to true
                            end if
                        end try
                        key code 53
                    end if

                    if toggled then
                        return "ok_menu"
                    end if

                    -- Strategy 2: Generic menu scan fallback
                    try
                        set targetItem2 to missing value
                        repeat with mbi2 in menu bar items of menu bar 1
                            try
                                click mbi2
                                delay 0.03
                                repeat with mi2 in menu items of menu 1 of mbi2
                                    try
                                        set itemName2 to (name of mi2 as text)
                                        if itemName2 contains "Zu Lieblingssongs hinzufügen" or itemName2 contains "Aus Lieblingssongs entfernen" or itemName2 contains "Liked Songs" or itemName2 contains "Lieblingssongs" or itemName2 contains "Save to Your Liked Songs" or itemName2 contains "Remove from your Liked Songs" then
                                            set targetItem2 to mi2
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                                key code 53
                                if targetItem2 is not missing value then exit repeat
                            end try
                        end repeat

                        if targetItem2 is not missing value then
                            click targetItem2
                            return "ok_menu_scan"
                        end if
                    end try

                    -- Strategy 3: keyboard shortcut fallback (varies by app version)
                    try
                        keystroke "l" using {command down, shift down}
                        return "ok_shortcut"
                    on error
                    end try

                    return "not_found"
                end tell
            end tell
            """

            let result = (self.runAppleScript(script) ?? "error").trimmingCharacters(in: .whitespacesAndNewlines)
            self.publishSpotifyLikeResult(result)
            self.publishSpotifyState()
        }
    }

    private func runSpotifyFocus() {
        spotifyQueue.async { [weak self] in
            guard let self else { return }
            let script = """
            tell application "Spotify" to activate
            """
            _ = self.runAppleScript(script)
        }
    }

    private func runNamedShortcut(name: String, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.08)
        }
        if process.isRunning {
            process.terminate()
            return false
        }

        _ = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0
    }

    private func detectSpotifyLikeShortcuts() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let names = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        func containsOne(_ s: String, _ terms: [String]) -> Bool {
            let lower = s.lowercased()
            return terms.contains { lower.contains($0) }
        }

        let matched = names.filter { n in
            containsOne(n, ["spotify"]) &&
            containsOne(n, ["like", "liked", "lieblings", "favorit", "favorite"])
        }
        return Array(Set(matched))
    }

    private func publishSpotifyState() {
        let state = fetchSpotifyState()
        DispatchQueue.main.async { [weak self] in
            self?.postSpotifyState(state)
        }
    }

    private func fetchSpotifyState() -> [String: Any] {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                set playerStateText to (player state as text)
                set trackName to ""
                set artistName to ""
                set albumName to ""
                set durationSec to 0
                set positionSec to 0
                set appVolume to 0

                try
                    set currentTrackRef to current track
                    set trackName to (name of currentTrackRef as text)
                    set artistName to (artist of currentTrackRef as text)
                    set albumName to (album of currentTrackRef as text)
                    set durationSec to ((duration of currentTrackRef) / 1000)
                    set positionSec to player position
                end try
                try
                    set appVolume to sound volume
                end try

                return "1" & linefeed & playerStateText & linefeed & trackName & linefeed & artistName & linefeed & albumName & linefeed & (durationSec as text) & linefeed & (positionSec as text) & linefeed & (appVolume as text)
            end tell
        else
            return "0" & linefeed & "stopped" & linefeed & "" & linefeed & "" & linefeed & "" & linefeed & "0" & linefeed & "0" & linefeed & "0"
        end if
        """

        let output = runAppleScript(script) ?? "0\nstopped\n\n\n\n0\n0\n0"
        let parts = output
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let running = (parts.indices.contains(0) ? parts[0] : "0") == "1"
        let playerState = parts.indices.contains(1) ? parts[1] : "stopped"
        let track = parts.indices.contains(2) ? parts[2] : ""
        let artist = parts.indices.contains(3) ? parts[3] : ""
        let album = parts.indices.contains(4) ? parts[4] : ""
        let duration = parseNumber(parts.indices.contains(5) ? parts[5] : "0")
        let position = parseNumber(parts.indices.contains(6) ? parts[6] : "0")
        let volume = parseNumber(parts.indices.contains(7) ? parts[7] : "0")

        return [
            "running": running,
            "playerState": playerState,
            "track": track,
            "artist": artist,
            "album": album,
            "duration": duration,
            "position": position,
            "volume": volume
        ]
    }

    private func postSpotifyState(_ payload: [String: Any]) {
        guard let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.handleNativeSpotifyState && window.handleNativeSpotifyState(\(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func publishSpotifyLikeResult(_ result: String) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { return }
            let escaped = result.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            let js = "window.handleNativeSpotifyLikeResult && window.handleNativeSpotifyLikeResult('\(escaped)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            log("AppleScript failed: \(error)")
            return nil
        }
        return result?.stringValue
    }

    private func parseNumber(_ raw: String) -> Double {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }

    private func runFocusShortcut(enabled: Bool) -> Bool {
        let shortcutName = enabled ? "FocusOn" : "FocusOff"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcutName]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            log("Shortcut \(shortcutName) failed to start: \(error)")
            return false
        }

        let timeout: TimeInterval = 6
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            log("Shortcut \(shortcutName) timed out after \(timeout)s")
            return false
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            log("Shortcut \(shortcutName) ok\(out.isEmpty ? "" : ": \(out)")")
            return true
        } else {
            log("Shortcut \(shortcutName) failed (\(process.terminationStatus))\(err.isEmpty ? "" : ": \(err)")")
            return false
        }
    }

    private func runAppleScriptDND(enabled: Bool) {
            let script: String
            if enabled {
                // Enable DND: open Kontrollzentrum, click Fokus checkbox (checkbox 2)
                script = """
                tell application "System Events"
                    tell process "ControlCenter"
                        -- Open Control Center
                        repeat with i in menu bar items of menu bar 1
                            try
                                if description of i is "Kontrollzentrum" or description of i is "Control Center" then
                                    click i
                                    exit repeat
                                end if
                            end try
                        end repeat
                        delay 1.5

                        try
                            set targetWindow to missing value
                            try
                                set targetWindow to window "Kontrollzentrum"
                            on error
                                set targetWindow to window "Control Center"
                            end try

                            -- Fokus is checkbox 2 in Control Center
                            set fokusCheckbox to checkbox 2 of group 1 of targetWindow
                            if value of fokusCheckbox is 0 then
                                click fokusCheckbox
                                delay 0.3
                            end if
                        on error errMsg
                            key code 53
                            return "error: " & errMsg
                        end try

                        key code 53
                        return "ok"
                    end tell
                end tell
                """
            } else {
                // Disable DND: Fokus menu bar item appears when DND is active
                script = """
                tell application "System Events"
                    tell process "ControlCenter"
                        -- Find the Fokus menu bar item (only visible when DND is active)
                        set fokusItem to missing value
                        repeat with i in menu bar items of menu bar 1
                            try
                                set d to description of i
                                if d starts with "Fokus" or d starts with "Focus" then
                                    set fokusItem to i
                                    exit repeat
                                end if
                            end try
                        end repeat

                        if fokusItem is missing value then
                            return "ok: DND already off"
                        end if

                        click fokusItem
                        delay 1.5

                        try
                            set targetWindow to missing value
                            try
                                set targetWindow to window "Kontrollzentrum"
                            on error
                                set targetWindow to window "Control Center"
                            end try

                            -- Robust: find the DND checkbox by label first, fallback to any active checkbox
                            set didToggle to false
                            set fallbackCheckbox to missing value
                            set allElems to entire contents of targetWindow

                            repeat with el in allElems
                                try
                                    if role of el is "AXCheckBox" then
                                        set checkboxValue to value of el
                                        if checkboxValue is 1 then
                                            if fallbackCheckbox is missing value then
                                                set fallbackCheckbox to el
                                            end if

                                            set labelText to ""
                                            try
                                                set labelText to (name of el as text)
                                            end try

                                            if (labelText contains "Nicht stören") or (labelText contains "Do Not Disturb") then
                                                click el
                                                delay 0.3
                                                set didToggle to true
                                                exit repeat
                                            end if
                                        end if
                                    end if
                                end try
                            end repeat

                            if didToggle is false and fallbackCheckbox is not missing value then
                                click fallbackCheckbox
                                delay 0.3
                                set didToggle to true
                            end if

                            if didToggle is false then
                                key code 53
                                return "error: no active focus checkbox found"
                            end if
                        on error errMsg
                            key code 53
                            return "error: " & errMsg
                        end try

                        key code 53
                        return "ok"
                    end tell
                end tell
                """
            }

            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            let result = appleScript?.executeAndReturnError(&error)
            if let error {
                log("DND \(enabled ? "ON" : "OFF") failed: \(error)")
            } else if let result = result?.stringValue {
                log("DND \(enabled ? "ON" : "OFF") result: \(result)")
            } else {
                log("DND \(enabled ? "ON" : "OFF") finished without string result")
            }
    }

    private func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogPath) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: debugLogPath)) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: debugLogPath))
            }
        }
    }
}

final class AppUpdater {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let assets: [Asset]
    }

    private let log: (String) -> Void
    private let status: (String, String) -> Void
    private let progress: (String) -> Void

    init(
        log: @escaping (String) -> Void,
        status: @escaping (String, String) -> Void,
        progress: @escaping (String) -> Void = { _ in }
    ) {
        self.log = log
        self.status = status
        self.progress = progress
    }

    func run() {
        let repo = (Bundle.main.object(forInfoDictionaryKey: "DeepTideUpdateRepo") as? String) ?? "Viralhouse/clock-app"
        guard let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            log("Updater: invalid releases URL")
            return
        }

        var req = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("DeepTide-Updater", forHTTPHeaderField: "User-Agent")
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try URLSession.shared.syncRequest(req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                log("Updater: GitHub API status \(http.statusCode). Is the repo private?")
                return
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            let currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
            let latestVersion = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            if compareVersions(latestVersion, currentVersion) <= 0 {
                log("Updater: already up-to-date (\(currentVersion))")
                status("DeepTide Update", "Already up-to-date (\(currentVersion)).")
                return
            }

            guard let asset = release.assets.first(where: { $0.name == "DeepTide.app.zip" }),
                  let assetURL = URL(string: asset.browser_download_url) else {
                log("Updater: no DeepTide.app.zip asset in latest release")
                status("DeepTide Update", "No installable asset found in latest release.")
                return
            }

            status("DeepTide Update", "Downloading version \(latestVersion)...")
            log("Updater: downloading \(asset.browser_download_url)")
            var assetReq = URLRequest(url: assetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 900)
            assetReq.setValue("DeepTide-Updater", forHTTPHeaderField: "User-Agent")
            if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
                assetReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (zipTempURL, assetResp) = try downloadRequestWithProgress(assetReq)
            if let http = assetResp as? HTTPURLResponse, http.statusCode >= 400 {
                log("Updater: asset download failed with status \(http.statusCode)")
                status("DeepTide Update", "Download failed (HTTP \(http.statusCode)).")
                return
            }

            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("deeptide-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let zipPath = tmpDir.appendingPathComponent("DeepTide.app.zip")
            if FileManager.default.fileExists(atPath: zipPath.path) {
                try FileManager.default.removeItem(at: zipPath)
            }
            try FileManager.default.copyItem(at: zipTempURL, to: zipPath)

            let scriptPath = tmpDir.appendingPathComponent("install-update.sh")
            try installScript().write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            let appPath = Bundle.main.bundlePath
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath.path, appPath, zipPath.path]
            try proc.run()
            log("Updater: installer launched, quitting app")
            status("DeepTide Update", "Installing update now. App will restart.")

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            log("Updater failed: \(error)")
            status("DeepTide Update", "Update failed: \(error.localizedDescription)")
        }
    }

    private func downloadRequestWithProgress(_ request: URLRequest) throws -> (URL, URLResponse) {
        let sem = DispatchSemaphore(value: 0)
        var outURL: URL?
        var outResp: URLResponse?
        var outErr: Error?

        let task = URLSession.shared.downloadTask(with: request) { url, response, error in
            outURL = url
            outResp = response
            outErr = error
            sem.signal()
        }
        task.resume()

        var lastProgressAt = Date.distantPast
        var lastReportedPercent = -1
        var lastObservedBytes: Int64 = 0
        var lastByteChangeAt = Date()
        var lastReportedChunk = -1

        while true {
            let waitResult = sem.wait(timeout: .now() + 1.0)
            if waitResult == .success {
                break
            }

            let received = max(task.countOfBytesReceived, 0)
            let expected = task.countOfBytesExpectedToReceive

            if received != lastObservedBytes {
                lastObservedBytes = received
                lastByteChangeAt = Date()
            }
            if Date().timeIntervalSince(lastByteChangeAt) > 90 {
                task.cancel()
                throw NSError(
                    domain: "DeepTideUpdater",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Download stalled. Please try again."]
                )
            }

            if expected > 0 {
                let percent = Int((Double(received) / Double(expected)) * 100.0)
                let shouldReport = percent >= lastReportedPercent + 5
                    || Date().timeIntervalSince(lastProgressAt) > 8
                if shouldReport {
                    lastReportedPercent = percent
                    lastProgressAt = Date()
                    let receivedMB = Double(received) / 1_048_576.0
                    let expectedMB = Double(expected) / 1_048_576.0
                    progress(String(format: "Downloading… %d%% (%.1f / %.1f MB)", min(percent, 100), receivedMB, expectedMB))
                }
            } else {
                let chunk = Int(received / 5_242_880) // 5 MB
                if chunk > lastReportedChunk {
                    lastReportedChunk = chunk
                    let receivedMB = Double(received) / 1_048_576.0
                    progress(String(format: "Downloading… %.1f MB", receivedMB))
                }
            }
        }

        if let outErr {
            throw outErr
        }
        guard let outURL, let outResp else {
            throw NSError(
                domain: "DeepTideUpdater",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No response from download request."]
            )
        }
        return (outURL, outResp)
    }

    private func installScript() -> String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        TARGET_APP="$1"
        ZIP_PATH="$2"
        APP_DIR="$(dirname "$TARGET_APP")"
        TMP_DIR="$(mktemp -d)"
        trap 'rm -rf "$TMP_DIR"' EXIT

        sleep 1
        ditto -x -k "$ZIP_PATH" "$TMP_DIR"
        NEW_APP="$TMP_DIR/DeepTide.app"
        if [[ ! -d "$NEW_APP" ]]; then
          NEW_APP="$(find "$TMP_DIR" -maxdepth 4 -type d -name "DeepTide.app" | head -n 1 || true)"
        fi
        if [[ ! -d "$NEW_APP" ]]; then
          echo "Updater: DeepTide.app not found in archive" >&2
          exit 1
        fi

        if [[ -w "$APP_DIR" ]]; then
          rm -rf "$TARGET_APP"
          cp -R "$NEW_APP" "$TARGET_APP"
        else
          /usr/bin/osascript <<APPLESCRIPT
        do shell script "rm -rf \\"$TARGET_APP\\" && cp -R \\"$NEW_APP\\" \\"$TARGET_APP\\"" with administrator privileges
        APPLESCRIPT
        fi

        xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
        open "$TARGET_APP"
        """
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        func parse(_ s: String) -> [Int] {
            let parts = s.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }
            return parts.isEmpty ? [0] : parts
        }
        let a = parse(lhs)
        let b = parse(rhs)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av < bv ? -1 : 1 }
        }
        return 0
    }
}

private extension URLSession {
    func syncRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
        let sem = DispatchSemaphore(value: 0)
        var outData = Data()
        var outResp: URLResponse?
        var outErr: Error?
        let task = dataTask(with: request) { data, response, error in
            outData = data ?? Data()
            outResp = response
            outErr = error
            sem.signal()
        }
        task.resume()
        sem.wait()
        if let outErr { throw outErr }
        guard let outResp else { throw NSError(domain: "DeepTideUpdater", code: -1) }
        return (outData, outResp)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var focusHandler = FocusMessageHandler()
    private let onboardingVersionKey = "onboarding_shown_v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()

        let screen = NSScreen.main!.frame
        let width: CGFloat = 700
        let height: CGFloat = 400
        let rect = NSRect(
            x: (screen.width - width) / 2,
            y: (screen.height - height) / 2,
            width: width,
            height: height
        )

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepTide"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.18, alpha: 1.0)

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(focusHandler, name: "focus")
        config.userContentController = contentController

        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        focusHandler.webView = webView
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")

        if let htmlURL = Bundle.main.url(forResource: "deeptide", withExtension: "html", subdirectory: "Web") {
            let webRoot = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: webRoot)
            logLocal("Loaded bundled web UI from \(htmlURL.path)")
        } else {
            let fallbackPath = NSString("~/claudetest.md/deeptide.html").expandingTildeInPath
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            webView.loadFileURL(fallbackURL, allowingReadAccessTo: fallbackURL.deletingLastPathComponent())
            logLocal("WARNING: bundled web UI missing, using fallback \(fallbackPath)")
        }

        window.contentView!.addSubview(webView)
        window.makeKeyAndOrderFront(nil)
        focusHandler.startSpotifyMonitoring()
        showOnboardingIfNeeded()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let missing = self.missingRequiredShortcuts()
            if !missing.isEmpty {
                DispatchQueue.main.async {
                    self.showMissingShortcutsAlert(missing: missing)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc private func checkForUpdatesMenuAction(_ sender: Any?) {
        focusHandler.requestUpdateFromNative()
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesMenuAction(_:)),
            keyEquivalent: "u"
        )
        updateItem.keyEquivalentModifierMask = [.command]
        updateItem.target = self
        appMenu.addItem(updateItem)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit DeepTide",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
    }

    private func missingRequiredShortcuts() -> [String] {
        let required = ["FocusOn", "FocusOff"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return required
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        return required.filter { !output.contains($0) }
    }

    private func showMissingShortcutsAlert(missing: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Required Shortcuts Missing"
        alert.informativeText = """
        DeepTide needs these Shortcuts: \(missing.joined(separator: ", "))

        Create them in the Shortcuts app:
        - FocusOn: Set Focus -> Do Not Disturb -> On
        - FocusOff: Set Focus -> Do Not Disturb -> Off
        """
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }

    private func showOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: onboardingVersionKey) { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Welcome to DeepTide"
        alert.informativeText = """
        Quick setup (one time):

        1) If macOS blocks opening:
           Right-click DeepTide.app -> Open -> Open.
        2) Grant Accessibility + Automation permissions when asked.
        3) Create Shortcuts:
           - FocusOn  (Do Not Disturb ON)
           - FocusOff (Do Not Disturb OFF)
        4) Updates:
           Use ↻ button or Cmd+U.
        """
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "Continue")
        let response = alert.runModal()
        defaults.set(true, forKey: onboardingVersionKey)
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }
}

private func logLocal(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/deeptide_debug.log"
        if FileManager.default.fileExists(atPath: path),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
