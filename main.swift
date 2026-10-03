import AppKit
import IOKit

// MARK: - pmset helpers

func run(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

/// The lid-closed-awake state is exposed by `pmset -g` as `SleepDisabled`.
/// NOTE: the setting name used to *write* it is `disablesleep`, but the key
/// printed by `pmset -g` is `SleepDisabled` (one word, capitalised).
func sleepDisabled() -> Bool {
    for line in run("/usr/bin/pmset", ["-g"]).split(separator: "\n") {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if parts.count >= 2, parts[0].lowercased() == "sleepdisabled" {
            return parts[1] == "1"
        }
    }
    return false
}

@discardableResult
func setSleepDisabled(_ on: Bool) -> Bool {
    _ = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"])
    return sleepDisabled() == on
}

// MARK: - Clamshell (lid-close) monitor

/// Watches the IOPMrootDomain for lid-close events via IOKit interest
/// notifications.  When the lid physically closes while lid-awake is active,
/// the internal display is blanked automatically with `pmset displaysleepnow`
/// — the same mechanism macOS uses in clamshell mode with an external display.
///
/// **Why this is needed:**  `disablesleep 1` is a brute-force flag that
/// prevents the *entire* sleep process, including the normal clamshell
/// transition that would turn off the internal panel.  Without an external
/// display to "hand off" to, macOS simply keeps the backlight on behind the
/// closed lid.  This monitor bridges that gap.
final class ClamshellMonitor {
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private let pmRootDomain: io_service_t

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return nil }
        pmRootDomain = service
    }

    deinit {
        stop()
        IOObjectRelease(pmRootDomain)
    }

    /// Returns `true` when the lid is physically closed (Hall-effect sensor).
    func isLidClosed() -> Bool {
        guard let prop = IORegistryEntryCreateCFProperty(
            pmRootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else {
            return false
        }
        return prop
    }

    /// Begin watching for lid-state changes on the current run loop.
    func start() {
        guard notifyPort == nil else { return }
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }

        let cfSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), cfSource, .defaultMode)

        // The C callback receives `refcon` (pointer to self) plus the
        // service and messageType.  We only care about general-interest
        // notifications which include clamshell state transitions.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(
            port,
            pmRootDomain,
            kIOGeneralInterest,
            { (refcon, _, _, _) in
                guard let refcon else { return }
                let monitor = Unmanaged<ClamshellMonitor>
                    .fromOpaque(refcon).takeUnretainedValue()
                monitor.handleChange()
            },
            selfPtr,
            &notifier
        )
    }

    func stop() {
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }

    /// Called on every IOPMrootDomain general-interest notification.
    /// If lid-awake is active and the lid just closed, blank the display
    /// so the backlight doesn't stay on behind the closed lid.
    private func handleChange() {
        guard sleepDisabled(), isLidClosed() else { return }
        // Small delay lets the lid sensor settle before blanking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }
}

// MARK: - Login item (LaunchAgent)

let bundleID = "com.lidawake.app"
let launchAgentLabel = "com.lidawake.login"
var launchAgentPath: String {
    NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"
}

func loginItemEnabled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentPath)
}

func setLoginItem(_ on: Bool) {
    let fm = FileManager.default
    if on {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(launchAgentLabel)</string>
          <key>ProgramArguments</key>
          <array><string>\(Bundle.main.executablePath ?? "")</string></array>
          <key>RunAtLoad</key><true/>
          <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", launchAgentPath])
    } else {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
        try? fm.removeItem(atPath: launchAgentPath)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var detailLabel: NSTextField!
    var toggleButton: NSButton!
    var loginCheckbox: NSButton!
    var item: NSStatusItem!
    var statusMenu: NSMenu!
    var clamshellMonitor: ClamshellMonitor?

    func applicationDidFinishLaunching(_ note: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }
        buildMenu()
        buildWindow()
        buildStatusItem()
        refresh()

        // Start monitoring the lid sensor so we can blank the display
        // automatically when the lid closes while lid-awake is active.
        clamshellMonitor = ClamshellMonitor()
        clamshellMonitor?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: UI

    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lid Awake",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Lid Awake", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Lid Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 250),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Lid Awake"
        window.isReleasedWhenClosed = false

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        statusLabel.alignment = .center

        detailLabel = NSTextField(wrappingLabelWithString: "")
        detailLabel.alignment = .center
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = NSFont.systemFont(ofSize: 12)

        let hintLabel = NSTextField(wrappingLabelWithString: "Lid Awake lives in your menu bar — click the cup icon for quick options.")
        hintLabel.alignment = .center
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.font = NSFont.systemFont(ofSize: 11)

        toggleButton = NSButton(title: "", target: self, action: #selector(toggleClicked))
        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .large
        toggleButton.keyEquivalent = "\r"

        loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(loginToggled))

        let stack = NSStackView(views: [statusLabel, detailLabel, toggleButton, loginCheckbox, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    func buildStatusItem() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Rebuilds the menu-bar menu (Caffeine-style): a status header, a toggle,
    /// launch-at-login, and About/Quit. Called whenever the state changes.
    func refreshMenu() {
        let on = sleepDisabled()
        let menu = NSMenu()

        let header = NSMenuItem(title: on ? "Lid Awake is active" : "Lid Awake is inactive",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let toggle = NSMenuItem(title: on ? "Disable lid-awake" : "Enable lid-awake",
                                action: #selector(menuToggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let screenOff = NSMenuItem(title: "Turn Screen Off",
                                   action: #selector(turnScreenOff), keyEquivalent: "")
        screenOff.target = self
        menu.addItem(screenOff)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(menuLoginToggle), keyEquivalent: "")
        login.target = self
        login.state = loginItemEnabled() ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let about = NSMenuItem(title: "About Lid Awake",
                               action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                               keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lid Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Don't attach the menu to the button: a primary (left) click toggles
        // the state directly, and the menu is only shown on a secondary
        // (right) click.
        statusMenu = menu
        item.menu = nil
    }

    func refresh() {
        let on = sleepDisabled()
        if on {
            statusLabel.stringValue = "Lid closed: Mac stays awake"
            detailLabel.stringValue = "The Mac keeps running when you shut the lid (no external display needed)."
            toggleButton.title = "Turn OFF  (sleep on lid close)"
        } else {
            statusLabel.stringValue = "Normal: sleeps on lid close"
            detailLabel.stringValue = "Shutting the lid will put the Mac to sleep, as usual."
            toggleButton.title = "Turn ON  (stay awake with lid shut)"
        }
        loginCheckbox.state = loginItemEnabled() ? .on : .off

        // Caffeine-style two-state menu-bar icon: filled cup = active,
        // hollow cup = inactive. Icon-only (no text), like Caffeine.
        let sym = on ? "cup.and.saucer.fill" : "cup.and.saucer"
        let img = NSImage(systemSymbolName: sym, accessibilityDescription: on ? "Lid Awake active" : "Lid Awake inactive")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.title = ""
        item.button?.toolTip = on
            ? "Lid Awake: active — click to turn off, right-click for menu"
            : "Lid Awake: inactive — click to turn on, right-click for menu"

        refreshMenu()
    }

    // MARK: Actions

    /// Primary (left) click toggles the setting without opening a menu;
    /// secondary (right) click opens the menu.
    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            item.menu = statusMenu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            toggleNow()
        }
    }

    func toggleNow() {
        if !setSleepDisabled(!sleepDisabled()) { showSudoersHelp(); return }
        refresh()
    }

    @objc func toggleClicked() {
        toggleNow()
    }

    @objc func loginToggled() {
        setLoginItem(loginCheckbox.state == .on)
        refresh()
    }

    @objc func menuLoginToggle() {
        setLoginItem(!loginItemEnabled())
        refresh()
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    /// Shown when the toggle fails, almost always because the passwordless
    /// sudoers rule is missing.
    func showSudoersHelp() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't change the setting"
        alert.informativeText = """
        Lid Awake needs a one-time passwordless sudo rule to change the \
        power-management setting. Run this in Terminal, then try again:

        printf '%s\\n' "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" \
          | sudo tee /etc/sudoers.d/lid-toggle >/dev/null
        sudo chmod 440 /etc/sudoers.d/lid-toggle
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func menuToggle() {
        toggleNow()
    }

    /// Blank the display immediately without sleeping the Mac. No sudo needed
    /// on recent macOS; the screen wakes on any mouse/keyboard input.
    @objc func turnScreenOff() {
        _ = run("/usr/bin/pmset", ["displaysleepnow"])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
