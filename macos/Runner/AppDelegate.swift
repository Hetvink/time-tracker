import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
    var statusItem: NSStatusItem?
    var methodChannel: FlutterMethodChannel?
    var statusMenu: NSMenu?
    var currentStatus: String = "Checked Out"
    var lastEventTime: Date = Date()
    var sleepStartTime: Date?
    var wakeTime: Date?
    var sleepThresholdSeconds: TimeInterval = 900 // Default: 15 minutes
    var midnightTimer: Timer? // Timer to monitor midnight transitions
    var windowTracker: ActiveWindowTracker? // Window/app activity tracker
    var breakDialogManager: BreakDialogManager? // Manager for break dialogs
    var recoveryDialogManager: RecoveryDialogManager? // Manager for recovery dialogs
    var isTrackingEnabled: Bool = false
    var isAuthenticated: Bool = false // Track authentication status
    
    override func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar icon
        setupMenuBar()
        
        // Setup platform channel
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
        methodChannel = FlutterMethodChannel(
            name: "com.attendance.tracker/system",
            binaryMessenger: controller.engine.binaryMessenger
        )
        
        setupMethodCallHandler()
        setupSystemEventMonitors()

        // Register as login item for auto-start
        registerAsLoginItem()

        // Start midnight monitor
        startMidnightMonitor()

        // Initialize window tracker
        windowTracker = ActiveWindowTracker { [weak self] appName, windowTitle, bundleId in
            self?.handleActivityChange(appName: appName, windowTitle: windowTitle, bundleId: bundleId)
        }
        
        // Initialize break dialog manager
        breakDialogManager = BreakDialogManager(methodChannel: methodChannel, mainFlutterWindow: mainFlutterWindow)
        
        // Initialize recovery dialog manager
        recoveryDialogManager = RecoveryDialogManager(methodChannel: methodChannel, mainFlutterWindow: mainFlutterWindow)

        // Don't show accessibility alert automatically - users can enable in Settings
        // checkAccessibilityPermissions()

        // Don't automatically trigger boot event at launch
        // Instead, it will be triggered manually after user logs in (via triggerBootEvent)
        // This ensures the auto check-in dialog only shows when user is authenticated
        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        //     self.notifySystemBoot()
        // }
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Time Trak")
                button.image?.isTemplate = true
            } else {
                // Fallback for older macOS versions - use text
                button.title = "⏰"
            }
        }
        
        statusMenu = NSMenu()
        
        // Status item (will be updated dynamically)
        let statusMenuItem = NSMenuItem(title: "Checked Out", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        statusMenu?.addItem(statusMenuItem)
        
        statusMenu?.addItem(NSMenuItem.separator())
        
        // Action items
        let checkInItem = NSMenuItem(title: "Check In", action: #selector(checkIn), keyEquivalent: "i")
        checkInItem.tag = 101
        statusMenu?.addItem(checkInItem)
        
        let checkOutItem = NSMenuItem(title: "Check Out", action: #selector(checkOut), keyEquivalent: "o")
        checkOutItem.tag = 102
        statusMenu?.addItem(checkOutItem)
        
        statusMenu?.addItem(NSMenuItem.separator())
        
        let breakInItem = NSMenuItem(title: "Break In", action: #selector(breakIn), keyEquivalent: "b")
        breakInItem.tag = 103
        statusMenu?.addItem(breakInItem)
        
        let breakOutItem = NSMenuItem(title: "Break Out", action: #selector(breakOut), keyEquivalent: "r")
        breakOutItem.tag = 104
        statusMenu?.addItem(breakOutItem)
        
        statusMenu?.addItem(NSMenuItem.separator())
        
        let openDashboardItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        statusMenu?.addItem(openDashboardItem)
        
        statusMenu?.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu?.addItem(quitItem)
        
        statusItem?.menu = statusMenu
    }
    
    func setupSystemEventMonitors() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        
        // Sleep detection
        notificationCenter.addObserver(
            self,
            selector: #selector(didSleepNotification),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        // Wake detection
        notificationCenter.addObserver(
            self,
            selector: #selector(didWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Screen lock detection
        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenLock),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        // Screen unlock detection
        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenUnlock),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }
    
    func notifySystemBoot() {
        // Only show dialog if user is authenticated
        guard isAuthenticated else {
            print("[BOOT] User not authenticated - skipping auto check-in dialog")
            return
        }
        
        // Show native confirmation dialog before auto check-in
        let alert = NSAlert()
        alert.messageText = "Auto Check-In"
        alert.informativeText = "System start detected. Do you want to check in now?"

        // Add buttons
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        // Set style
        alert.alertStyle = .informational

        // Ensure window is visible and show dialog on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Play sound
            NSSound.beep()

            // Activate app
            NSApp.activate(ignoringOtherApps: true)

            // Show as floating window
            alert.window.level = .floating

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // User clicked "Yes" - send boot event immediately
                print("[BOOT] User confirmed auto check-in - sending boot event")

                // Send the boot event directly via method channel
                self.methodChannel?.invokeMethod("onSystemEvent", arguments: ["event": "boot"]) { result in
                    if let error = result as? FlutterError {
                        print("[BOOT] Error sending boot event: \(error.message ?? "unknown")")
                    } else {
                        print("[BOOT] Boot event sent successfully")
                    }
                }
            } else {
                // User clicked "No"
                print("[BOOT] User cancelled auto check-in")
            }
        }
    }
    
    func sendSystemEvent(type: String) {
        methodChannel?.invokeMethod("onSystemEvent", arguments: ["event": type])
    }

    func startMidnightMonitor() {
        // Schedule timer to fire at next midnight
        scheduleNextMidnightCheck()
    }

    func scheduleNextMidnightCheck() {
        midnightTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()

        // Get tomorrow's start (next midnight)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.startOfDay(for: tomorrow) as Date? else {
            return
        }

        let timeInterval = nextMidnight.timeIntervalSince(now)

        print("[MIDNIGHT] Scheduling next midnight check in \(timeInterval) seconds at \(nextMidnight)")

        midnightTimer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: #selector(handleMidnight),
            userInfo: nil,
            repeats: false
        )
    }

    @objc func handleMidnight() {
        print("[MIDNIGHT] Midnight detected, notifying Flutter")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        methodChannel?.invokeMethod("onSystemEvent", arguments: [
            "event": "midnight",
            "timestamp": formatter.string(from: Date())
        ])

        // Schedule next midnight check
        scheduleNextMidnightCheck()
    }
    
    func sendLongSleepEvent(duration: TimeInterval, sleepStart: Date, wakeTime: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        methodChannel?.invokeMethod("onSystemEvent", arguments: [
            "event": "longSleep",
            "duration": duration,
            "sleepStart": formatter.string(from: sleepStart),
            "wakeTime": formatter.string(from: wakeTime)
        ])
    }
    
    @objc func didSleepNotification() {
        print("[SLEEP] System going to sleep at \(Date())")
        sleepStartTime = Date()
        sendSystemEvent(type: "sleep")
    }
    
    @objc func didWakeNotification() {
        print("[WAKE] System woke up at \(Date())")
        wakeTime = Date()

        // Check if sleep duration exceeds threshold
        if let sleepStart = sleepStartTime {
            let sleepDuration = wakeTime!.timeIntervalSince(sleepStart)

            print("[WAKE] Sleep duration: \(sleepDuration / 60) minutes")
            print("[WAKE] Threshold: \(sleepThresholdSeconds / 60) minutes")
            print("[WAKE] Exceeds threshold: \(sleepDuration >= sleepThresholdSeconds)")

            if sleepDuration >= sleepThresholdSeconds {
                print("[WAKE] Long sleep detected - scheduling dialog after 2 second delay")

                // CRITICAL FIX: Add delay to allow system to fully wake up
                // After long sleep (>20 min), macOS needs time to restore display
                // and user session before showing dialogs
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    print("[WAKE] Delay complete - showing break dialog")
                    self.breakDialogManager?.showBreakConfirmationAlert(
                        sleepStart: sleepStart,
                        wakeTime: self.wakeTime!,
                        duration: sleepDuration
                    )
                }
            } else {
                print("[WAKE] Sleep duration below threshold - no dialog needed")
            }
        } else {
            print("[WAKE] No sleep start time recorded")
        }

        sendSystemEvent(type: "wake")
        sleepStartTime = nil
    }
    
    @objc func handleScreenLock() {
        print("[SCREEN LOCK] Screen locked at \(Date())")
        sleepStartTime = Date()
        // Don't trigger any attendance action - just track the time
    }
    
    @objc func handleScreenUnlock() {
        print("[SCREEN UNLOCK] Screen unlocked at \(Date())")
        wakeTime = Date()

        // Check if screen lock duration exceeds threshold
        if let sleepStart = sleepStartTime {
            let sleepDuration = wakeTime!.timeIntervalSince(sleepStart)

            print("[SCREEN UNLOCK] Lock duration: \(sleepDuration / 60) minutes")
            print("[SCREEN UNLOCK] Threshold: \(sleepThresholdSeconds / 60) minutes")
            print("[SCREEN UNLOCK] Exceeds threshold: \(sleepDuration >= sleepThresholdSeconds)")

            if sleepDuration >= sleepThresholdSeconds {
                print("[SCREEN UNLOCK] Long screen lock detected - scheduling dialog after 2 second delay")

                // CRITICAL FIX: Add delay to allow system to fully wake up
                // After long lock (>20 min), macOS needs time to restore display
                // and user session before showing dialogs
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    print("[SCREEN UNLOCK] Delay complete - showing break dialog")
                    self.breakDialogManager?.showBreakConfirmationAlert(
                        sleepStart: sleepStart,
                        wakeTime: self.wakeTime!,
                        duration: sleepDuration
                    )
                }
            } else {
                print("[SCREEN UNLOCK] Lock duration below threshold - no dialog needed")
            }
        } else {
            print("[SCREEN UNLOCK] No lock start time recorded")
        }

        sleepStartTime = nil
        // Don't trigger any attendance action
    }
    

    
    @objc func checkIn() {
        methodChannel?.invokeMethod("onUserAction", arguments: ["action": "checkIn"])
    }
    
    @objc func checkOut() {
        methodChannel?.invokeMethod("onUserAction", arguments: ["action": "checkOut"])
    }
    
    @objc func breakIn() {
        methodChannel?.invokeMethod("onUserAction", arguments: ["action": "breakIn"])
    }
    
    @objc func breakOut() {
        methodChannel?.invokeMethod("onUserAction", arguments: ["action": "breakOut"])
    }
    
    @objc func openDashboard() {
        // Show and bring the main window to front
        mainFlutterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupMethodCallHandler() {
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "updateMenuBar":
                if let args = call.arguments as? [String: Any],
                   let status = args["status"] as? String {
                    self?.updateMenuBarStatus(status)
                    result(nil)
                }
            case "updateMenuItems":
                if let args = call.arguments as? [String: Any],
                   let enabledItems = args["enabledItems"] as? [String] {
                    self?.updateMenuItems(enabledItems)
                    result(nil)
                }
            case "getAutoStartStatus":
                let status = self?.getAutoStartStatus() ?? false
                result(status)
            case "setAutoStart":
                if let args = call.arguments as? [String: Any],
                   let enabled = args["enabled"] as? Bool {
                    self?.setAutoStart(enabled: enabled, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing enabled argument", details: nil))
                }
            case "openSystemPreferences":
                self?.openSystemPreferences()
                result(nil)
            case "setSleepThreshold":
                if let args = call.arguments as? [String: Any],
                   let seconds = args["seconds"] as? Int {
                    self?.setSleepThreshold(seconds: seconds)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing seconds argument", details: nil))
                }
            case "startActivityTracking":
                self?.startActivityTracking()
                result(nil)
            case "stopActivityTracking":
                self?.stopActivityTracking()
                result(nil)
            case "getCurrentActivity":
                if let activity = self?.windowTracker?.getCurrentActivity() {
                    result([
                        "appName": activity.appName,
                        "windowTitle": activity.windowTitle as Any,
                        "bundleId": activity.bundleId as Any
                    ])
                } else {
                    result(nil)
                }
            case "getAccessibilityPermissionStatus":
                let status = AXIsProcessTrusted()
                result(status)
            case "openAccessibilityPreferences":
                self?.openAccessibilityPreferences()
                result(nil)
            case "setTrackingInterval":
                if let args = call.arguments as? [String: Any],
                   let seconds = args["seconds"] as? Int {
                    self?.windowTracker?.updateTrackingInterval(TimeInterval(seconds))
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing seconds argument", details: nil))
                }
            case "setAuthenticationStatus":
                if let args = call.arguments as? [String: Any],
                   let isAuthenticated = args["isAuthenticated"] as? Bool {
                    self?.isAuthenticated = isAuthenticated
                    print("[AUTH] Authentication status updated: \(isAuthenticated)")
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing isAuthenticated argument", details: nil))
                }
            case "triggerBootEvent":
                // Manually trigger boot event (called after successful login)
                print("[BOOT] Manually triggering boot event after login")
                self?.notifySystemBoot()
                result(nil)
            case "showRecoveryDialog":
                if let args = call.arguments as? [String: Any],
                   let checkInTimeStr = args["checkInTime"] as? String,
                   let daysMissing = args["daysMissing"] as? Int {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    
                    guard let checkInTime = formatter.date(from: checkInTimeStr) else {
                        result(FlutterError(code: "INVALID_DATE", message: "Invalid check-in time format", details: nil))
                        return
                    }
                    
                    var lastSeenTime: Date? = nil
                    if let lastSeenStr = args["lastSeenTime"] as? String {
                        lastSeenTime = formatter.date(from: lastSeenStr)
                    }
                    
                    print("[RECOVERY] Showing recovery dialog for session from \(checkInTime)")
                    self?.recoveryDialogManager?.showRecoveryConfirmationAlert(
                        checkInTime: checkInTime,
                        lastSeenTime: lastSeenTime,
                        daysMissing: daysMissing
                    )
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    
    func updateMenuBarStatus(_ status: String) {
        DispatchQueue.main.async {
            // Update status text in menu
            if let menu = self.statusMenu {
                for item in menu.items {
                    if item.tag == 100 {
                        item.title = status
                        break
                    }
                }
            }

            // Update menu bar button with icon based on status
            if let button = self.statusItem?.button {
                // Determine icon based on status
                var iconName = "clock"

                if status.contains("Working") {
                    iconName = "clock.fill"  // Filled clock for working
                } else if status.contains("Break") {
                    iconName = "cup.and.saucer.fill"  // Coffee cup for break
                } else if status.contains("Checked Out") {
                    iconName = "clock.badge.xmark"  // Clock with X for checked out
                }

                // Update icon (macOS 11+)
                if #available(macOS 11.0, *) {
                    button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Time Trak")
                    button.image?.isTemplate = true  // Allow system to color it
                }

                // Update text with status
                button.title = " " + status  // Space for padding after icon
            }
        }
    }
    
    func updateMenuItems(_ enabledItems: [String]) {
        DispatchQueue.main.async {
            guard let menu = self.statusMenu else { return }
            
            for item in menu.items {
                // Enable/disable based on the list
                if item.title == "Check In" {
                    item.isEnabled = enabledItems.contains("Check In")
                } else if item.title == "Check Out" {
                    item.isEnabled = enabledItems.contains("Check Out")
                } else if item.title == "Break In" {
                    item.isEnabled = enabledItems.contains("Break In")
                } else if item.title == "Break Out" {
                    item.isEnabled = enabledItems.contains("Break Out")
                }
            }
        }
    }
    
    func registerAsLoginItem() {
        // For macOS 13+, use SMAppService
        if #available(macOS 13.0, *) {
            do {
                let status = SMAppService.mainApp.status
                print("Auto-start status: \(status.rawValue)")
                
                if status == .notRegistered {
                    try SMAppService.mainApp.register()
                    print("Successfully registered as login item")
                } else if status == .enabled {
                    print("Already registered as login item")
                }
            } catch {
                print("Failed to register as login item: \(error)")
                print("User can manually add to Login Items in System Preferences")
            }
        } else {
            print("Auto-start requires macOS 13.0 or later")
            print("User can manually add to Login Items in System Preferences")
        }
    }
    
    func getAutoStartStatus() -> Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled
        }
        return false
    }
    
    func setAutoStart(enabled: Bool, result: @escaping FlutterResult) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                        print("Auto-start enabled")
                        result(true)
                    } else {
                        print("Auto-start already enabled")
                        result(true)
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        print("Auto-start disabled")
                        result(true)
                    } else {
                        print("Auto-start already disabled")
                        result(true)
                    }
                }
            } catch {
                print("Failed to change auto-start: \(error)")
                result(FlutterError(
                    code: "AUTO_START_ERROR",
                    message: "Failed to change auto-start: \(error.localizedDescription)",
                    details: nil
                ))
            }
        } else {
            result(FlutterError(
                code: "UNSUPPORTED_VERSION",
                message: "Auto-start requires macOS 13.0 or later. Please add manually in System Preferences > General > Login Items",
                details: nil
            ))
        }
    }
    
    func openSystemPreferences() {
        if #available(macOS 13.0, *) {
            // Open Login Items in System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Open Users & Groups preferences for older macOS
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func setSleepThreshold(seconds: Int) {
        sleepThresholdSeconds = TimeInterval(seconds)
        print("[THRESHOLD] Sleep threshold updated to \(seconds) seconds (\(seconds / 60) minutes)")
    }

    // MARK: - Activity Tracking Methods

    func startActivityTracking() {
        guard !isTrackingEnabled else {
            print("[TRACKER] Activity tracking already enabled")
            return
        }

        print("[TRACKER] Starting activity tracking")
        isTrackingEnabled = true
        windowTracker?.startTracking()
    }

    func stopActivityTracking() {
        guard isTrackingEnabled else {
            print("[TRACKER] Activity tracking already disabled")
            return
        }

        print("[TRACKER] Stopping activity tracking")
        isTrackingEnabled = false
        windowTracker?.stopTracking()
    }

    func handleActivityChange(appName: String, windowTitle: String?, bundleId: String?) {
        guard isTrackingEnabled else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var args: [String: Any] = [
            "event": "activityChange",
            "appName": appName,
            "timestamp": formatter.string(from: Date())
        ]

        if let windowTitle = windowTitle {
            args["windowTitle"] = windowTitle
        }

        if let bundleId = bundleId {
            args["bundleId"] = bundleId
        }

        methodChannel?.invokeMethod("onActivityChange", arguments: args)
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background even when window is closed
        return false
    }
    
    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // Handle URL callbacks from Google Sign-In
    override func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("[AUTH] Received URL callback: \(url)")
            // Let Google Sign-In handle the callback URL
            if url.scheme?.hasPrefix("com.googleusercontent.apps") == true {
                print("[AUTH] Processing Google Sign-In callback")
            }
        }
    }
    
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let semaphore = DispatchSemaphore(value: 0)
        
        methodChannel?.invokeMethod("onSystemEvent", arguments: ["event": "shutdown"]) { _ in
            semaphore.signal()
        }
        
        // Wait max 3 seconds for Flutter to handle shutdown
        _ = semaphore.wait(timeout: .now() + 3.0)
        
        return .terminateNow
    }
    
    
    override func applicationWillTerminate(_ notification: Notification) {
        print("Application will terminate")
    }

    // MARK: - Accessibility Permissions Check

    func checkAccessibilityPermissions() {
        // Check if we've already shown the alert
        let hasShownAlert = UserDefaults.standard.bool(forKey: "HasShownAccessibilityAlert")
        
        // Check if accessibility is already enabled
        let accessEnabled = AXIsProcessTrusted()
        
        if !accessEnabled && !hasShownAlert {
            // Show alert after a short delay to ensure the app is fully launched
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showAccessibilityPermissionAlert()
            }
        }
    }
    
    func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = """
        Time Trak needs Accessibility permissions to track window titles.
        
        Without these permissions, only application names will be tracked.
        
        To enable:
        1. Click "Open System Preferences" below
        2. Click the lock icon and enter your password
        3. Enable the checkbox next to "time_trak"
        4. Restart Time Trak
        
        You can also enable this later in:
        System Preferences → Security & Privacy → Privacy → Accessibility
        """
        
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Don't Show Again")
        
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open System Preferences
            openAccessibilityPreferences()
            // Mark as shown so we don't show it again
            UserDefaults.standard.set(true, forKey: "HasShownAccessibilityAlert")
        } else if response == .alertThirdButtonReturn {
            // Don't show again
            UserDefaults.standard.set(true, forKey: "HasShownAccessibilityAlert")
        }
        // If "Remind Me Later", don't set the flag
    }
    
    func openAccessibilityPreferences() {
        // For macOS 13+, open Accessibility in System Settings
        if #available(macOS 13.0, *) {
            // Use the correct URL scheme for System Settings
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        } else {
            // For older macOS versions, use System Preferences
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Break Dialog Manager
class BreakDialogManager {
    private var methodChannel: FlutterMethodChannel?
    private weak var mainFlutterWindow: NSWindow?
    private var isShowingBreakDialog: Bool = false
    
    init(methodChannel: FlutterMethodChannel?, mainFlutterWindow: NSWindow?) {
        self.methodChannel = methodChannel
        self.mainFlutterWindow = mainFlutterWindow
    }
    
    func showBreakConfirmationAlert(sleepStart: Date, wakeTime: Date, duration: TimeInterval) {
        // Prevent duplicate dialogs
        if isShowingBreakDialog {
            print("[BREAK DIALOG] Already showing - skipping duplicate")
            return
        }

        isShowingBreakDialog = true
        print("[BREAK DIALOG] Showing break confirmation dialog")
        print("[BREAK DIALOG] Duration: \(duration / 60) minutes")
        print("[BREAK DIALOG] Sleep start: \(sleepStart)")
        print("[BREAK DIALOG] Wake time: \(wakeTime)")

        // Calculate time string first for use in title
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        var timeString = ""
        if hours > 0 {
            timeString = "\(hours) hour\(hours == 1 ? "" : "s")"
            if remainingMinutes > 0 {
                timeString += " and \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
            }
        } else {
            timeString = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }

        let alert = NSAlert()
        // Show time duration in the title for immediate visibility
        alert.messageText = "Are you on break? (Idle for \(timeString))"

        alert.informativeText = "Were you on a break during this time?\n\nClick 'Yes, I was on break' if you were on break.\nClick 'No, I was working' if you were working (this time will count as work time)."

        alert.addButton(withTitle: "Yes, I was on break")
        alert.addButton(withTitle: "No, I was working")

        // Use warning alert style for better visibility
        alert.alertStyle = .warning

        // Track if user has responded
        var hasResponded = false
        let responseLock = NSLock()

        // Auto-dismiss timer - defaults to "was on break" after 30 seconds
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            responseLock.lock()
            defer { responseLock.unlock() }
            
            if !hasResponded {
                hasResponded = true
                print("[BREAK DIALOG] Timed out after 30 seconds - defaulting to 'was on break'")
                
                // Close the alert window
                DispatchQueue.main.async {
                    NSApp.abortModal()
                }
                
                // Send default response (yes, was on break)
                self?.sendBreakConfirmation(wasOnBreak: true, sleepStart: sleepStart, wakeTime: wakeTime, note: nil)
            }
        }

        // Show alert on main thread with aggressive activation
        DispatchQueue.main.async { [weak self] in
            // Play system sound multiple times to get attention
            NSSound.beep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSSound.beep()
            }

            // Activate app with highest priority
            NSApp.activate(ignoringOtherApps: true)

            // Make the main window key first
            self?.mainFlutterWindow?.makeKeyAndOrderFront(nil)

            // Small delay to ensure window activation completes
            Thread.sleep(forTimeInterval: 0.1)

            // Set window level to floating BEFORE showing (highest non-modal level)
            alert.window.level = .floating

            // Make sure the window moves to the active space and stays on top
            alert.window.collectionBehavior = [.moveToActiveSpace, .transient]

            // Force window to front
            alert.window.orderFrontRegardless()

            print("[BREAK DIALOG] Presenting dialog to user with sound alert and forced activation")
            let response = alert.runModal()
            
            responseLock.lock()
            defer { responseLock.unlock() }
            
            // Only process if we haven't already timed out
            if !hasResponded {
                hasResponded = true
                timer.invalidate()

                let wasOnBreak = (response == .alertFirstButtonReturn)
                print("[BREAK DIALOG] User clicked: \(wasOnBreak ? "Yes (on break)" : "No (working)")")

                // If user was working, ask for a note
                if !wasOnBreak {
                    self?.showWorkNoteDialog(sleepStart: sleepStart, wakeTime: wakeTime)
                } else {
                    self?.sendBreakConfirmation(wasOnBreak: wasOnBreak, sleepStart: sleepStart, wakeTime: wakeTime, note: nil)
                }
            } else {
                print("[BREAK DIALOG] User responded after timeout - ignoring")
            }
        }
    }
    
    private func showWorkNoteDialog(sleepStart: Date, wakeTime: Date) {
        print("[WORK NOTE DIALOG] Showing work note dialog")

        // Ensure we're on the main thread with a small delay to let the first dialog close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = "What were you working on?"
            alert.informativeText = "Please provide a note about what you were working on during this time.\n\nThis note is required to record work time."

            alert.addButton(withTitle: "Submit")
            alert.addButton(withTitle: "Cancel") // Index 1001 (NSAlertSecondButtonReturn)

            // Create text field for note input
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
            textField.placeholderString = "E.g., Working on client project, debugging issue..."
            textField.maximumNumberOfLines = 3
            alert.accessoryView = textField

            alert.alertStyle = .informational

            // Play system sound to get attention
            NSSound.beep()

            // Activate app with highest priority
            NSApp.activate(ignoringOtherApps: true)

            // Make the main window key first
            self.mainFlutterWindow?.makeKeyAndOrderFront(nil)

            // Set window level to floating
            alert.window.level = .floating
            alert.window.collectionBehavior = [.moveToActiveSpace, .transient]

            // Force window to front (CRITICAL: without this the dialog stays hidden behind other windows)
            alert.window.orderFrontRegardless()

            print("[WORK NOTE DIALOG] Presenting note dialog to user")
            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Submit
                let note = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if note.isEmpty {
                    // Show error if note is empty
                    print("[WORK NOTE DIALOG] Note is empty - showing validation error")

                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Note Required"
                    errorAlert.informativeText = "Please provide a note to record work time, or click Cancel to go back."
                    errorAlert.alertStyle = .warning
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.window.level = .floating
                    errorAlert.window.orderFrontRegardless()
                    errorAlert.runModal()

                    // Show the note dialog again
                    self.showWorkNoteDialog(sleepStart: sleepStart, wakeTime: wakeTime)
                } else {
                    print("[WORK NOTE DIALOG] User submitted note: \(note)")
                    self.sendBreakConfirmation(wasOnBreak: false, sleepStart: sleepStart, wakeTime: wakeTime, note: note)
                }
            } else {
                // Cancel (NSAlertSecondButtonReturn or others)
                print("[WORK NOTE DIALOG] User cancelled - showing first dialog again")
                
                self.isShowingBreakDialog = false
                
                // Show the original dialog again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.showBreakConfirmationAlert(sleepStart: sleepStart, wakeTime: wakeTime, duration: wakeTime.timeIntervalSince(sleepStart))
                }
            }
        }
    }
    
    private func sendBreakConfirmation(wasOnBreak: Bool, sleepStart: Date, wakeTime: Date, note: String?) {
        print("Sending break confirmation: wasOnBreak=\(wasOnBreak), note=\(note ?? "none")")

        // Send response to Flutter
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var arguments: [String: Any] = [
            "wasOnBreak": wasOnBreak,
            "sleepStart": formatter.string(from: sleepStart),
            "wakeTime": formatter.string(from: wakeTime)
        ]

        if let note = note {
            arguments["note"] = note
        }

        methodChannel?.invokeMethod("onBreakConfirmation", arguments: arguments)

        // Reset flag after sending - this signifies the END of the interaction
        isShowingBreakDialog = false
        print("Break dialog flag reset")
    }
}
