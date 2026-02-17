import Cocoa
import WebKit

class FocusMessageHandler: NSObject, WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "start":
            setDND(enabled: true)
        case "stop":
            setDND(enabled: false)
        default:
            break
        }
    }

    private func setDND(enabled: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
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

                            -- In the Fokus panel, checkbox 1 is "Nicht stören" toggle
                            set dndCheckbox to checkbox 1 of group 1 of targetWindow
                            if value of dndCheckbox is 1 then
                                click dndCheckbox
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
            }

            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            let result = appleScript?.executeAndReturnError(&error)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var focusHandler = FocusMessageHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        let htmlPath = NSString("~/claudetest.md/clock.html").expandingTildeInPath
        let url = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())

        window.contentView!.addSubview(webView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
