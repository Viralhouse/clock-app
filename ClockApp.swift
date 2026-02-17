import Cocoa
import WebKit

class FocusMessageHandler: NSObject, WKScriptMessageHandler {
    private let debugLogPath = "/tmp/clock_debug.log"

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let action: String?
        if let body = message.body as? [String: Any] {
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
        default:
            break
        }
    }

    func requestUpdateFromNative() {
        performInAppUpdate()
    }

    private func performInAppUpdate() {
        showUpdateAlert(title: "Clock Update", message: "Checking for updates...")
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let updater = AppUpdater(
                log: log,
                status: { [weak self] title, message in
                    self?.showUpdateAlert(title: title, message: message)
                }
            )
            updater.run()
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

    init(
        log: @escaping (String) -> Void,
        status: @escaping (String, String) -> Void
    ) {
        self.log = log
        self.status = status
    }

    func run() {
        let repo = (Bundle.main.object(forInfoDictionaryKey: "ClockUpdateRepo") as? String) ?? "Viralhouse/clock-app"
        guard let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            log("Updater: invalid releases URL")
            return
        }

        var req = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("ClockApp-Updater", forHTTPHeaderField: "User-Agent")
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
                status("Clock Update", "Already up-to-date (\(currentVersion)).")
                return
            }

            guard let asset = release.assets.first(where: { $0.name == "Clock.app.zip" }),
                  let assetURL = URL(string: asset.browser_download_url) else {
                log("Updater: no Clock.app.zip asset in latest release")
                status("Clock Update", "No installable asset found in latest release.")
                return
            }

            status("Clock Update", "Downloading version \(latestVersion)...")
            log("Updater: downloading \(asset.browser_download_url)")
            var assetReq = URLRequest(url: assetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
            assetReq.setValue("ClockApp-Updater", forHTTPHeaderField: "User-Agent")
            if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
                assetReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (zipData, assetResp) = try URLSession.shared.syncRequest(assetReq)
            if let http = assetResp as? HTTPURLResponse, http.statusCode >= 400 {
                log("Updater: asset download failed with status \(http.statusCode)")
                status("Clock Update", "Download failed (HTTP \(http.statusCode)).")
                return
            }

            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("clock-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let zipPath = tmpDir.appendingPathComponent("Clock.app.zip")
            try zipData.write(to: zipPath)

            let scriptPath = tmpDir.appendingPathComponent("install-update.sh")
            try installScript().write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            let appPath = Bundle.main.bundlePath
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath.path, appPath, zipPath.path]
            try proc.run()
            log("Updater: installer launched, quitting app")
            status("Clock Update", "Installing update now. App will restart.")

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            log("Updater failed: \(error)")
            status("Clock Update", "Update failed: \(error.localizedDescription)")
        }
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
        NEW_APP="$TMP_DIR/Clock.app"
        if [[ ! -d "$NEW_APP" ]]; then
          echo "Updater: Clock.app not found in archive" >&2
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
            let cleaned = s.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            if cleaned.isEmpty { return [0] }
            return cleaned.split(separator: ".").map { Int($0) ?? 0 }
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
        guard let outResp else { throw NSError(domain: "ClockUpdater", code: -1) }
        return (outData, outResp)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var focusHandler = FocusMessageHandler()

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
        window.title = "Clock"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.18, alpha: 1.0)

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(focusHandler, name: "focus")
        config.userContentController = contentController

        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")

        if let htmlURL = Bundle.main.url(forResource: "clock", withExtension: "html", subdirectory: "Web") {
            let webRoot = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: webRoot)
            logLocal("Loaded bundled web UI from \(htmlURL.path)")
        } else {
            let fallbackPath = NSString("~/claudetest.md/clock.html").expandingTildeInPath
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            webView.loadFileURL(fallbackURL, allowingReadAccessTo: fallbackURL.deletingLastPathComponent())
            logLocal("WARNING: bundled web UI missing, using fallback \(fallbackPath)")
        }

        window.contentView!.addSubview(webView)
        window.makeKeyAndOrderFront(nil)

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
            title: "Quit Clock",
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
        Clock needs these Shortcuts: \(missing.joined(separator: ", "))

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
}

private func logLocal(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/clock_debug.log"
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
