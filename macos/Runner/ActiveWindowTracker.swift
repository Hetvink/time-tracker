import Cocoa
import ApplicationServices

class ActiveWindowTracker {
    private var lastTrackedApp: String?
    private var lastTrackedWindow: String?
    private var lastTrackedBundleId: String?
    private var lastTrackTime: Date?
    private var onActivityChange: ((String, String?, String?) -> Void)?
    private var isTracking = false

    // Observers for workspace notifications
    private var activateObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?

    // Timer to detect title changes within the same app (in-app navigation)
    private var titlePollTimer: Timer?

    // Cache permission status to avoid repeated system calls
    private var cachedPermissionStatus: Bool?
    private var permissionCheckTime: Date?
    private let permissionCacheDuration: TimeInterval = 5.0 // Cache for 5 seconds

    init(onActivityChange: @escaping (String, String?, String?) -> Void) {
        self.onActivityChange = onActivityChange
    }

    func startTracking() {
        guard !isTracking else {
            print("[TRACKER] Already tracking")
            return
        }

        // Request accessibility permissions
        requestAccessibilityPermissions()

        isTracking = true

        // Subscribe to app activation notifications (real-time window focus changes)
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }

        // Track immediately to get current active window
        trackActiveWindow()

        // Poll every 2 seconds to detect title changes WITHIN the same app
        // (macOS has no notification for in-app navigation, polling is required)
        titlePollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.trackActiveWindow()
        }

        print("[TRACKER] Real-time activity tracking started (with 2s in-app title polling)")
    }

    func stopTracking() {
        guard isTracking else { return }

        // Remove observers
        if let observer = activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activateObserver = nil
        }

        // Stop in-app title polling timer
        titlePollTimer?.invalidate()
        titlePollTimer = nil

        isTracking = false
        print("[TRACKER] Activity tracking stopped")
    }

    func updateTrackingInterval(_ interval: TimeInterval) {
        // No longer needed with real-time tracking, but keeping for API compatibility
        print("[TRACKER] Real-time tracking active - polling interval not used")
    }

    private func handleAppActivation(_ notification: Notification) {
        // Called immediately when any app becomes active (gets focus)
        trackActiveWindow()
    }

    // MARK: - Permission Checking with Caching

    /// Check accessibility permission with caching to prevent repeated system calls
    /// This avoids triggering permission dialogs multiple times in quick succession
    private func checkPermissionStatus() -> Bool {
        let now = Date()

        // Return cached value if still valid
        if let cached = cachedPermissionStatus,
           let checkTime = permissionCheckTime,
           now.timeIntervalSince(checkTime) < permissionCacheDuration {
            return cached
        }

        // Cache expired or not set - check permission
        let status = AXIsProcessTrusted()
        cachedPermissionStatus = status
        permissionCheckTime = now

        return status
    }

    private func requestAccessibilityPermissions() {
        // Use cached permission check to avoid repeated system calls
        let accessEnabled = checkPermissionStatus()

        if !accessEnabled {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("[TRACKER] ⚠️  ACCESSIBILITY PERMISSIONS REQUIRED")
            print("[TRACKER] Window titles cannot be tracked without permissions")
            print("[TRACKER] Please enable in Settings page:")
            print("[TRACKER]   Click 'Open System Settings' under Accessibility Permission")
            print("[TRACKER] Or manually enable in:")
            print("[TRACKER]   System Settings → Privacy & Security → Accessibility")
            print("[TRACKER]   Then add 'time_trak' to the list")
            print("[TRACKER] Only app names will be tracked until permissions are granted")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } else {
            print("[TRACKER] ✓ Accessibility permissions granted - window titles will be tracked")
        }
    }

    @objc private func trackActiveWindow() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            print("[TRACKER] No frontmost application found")
            return
        }

        let appName = activeApp.localizedName ?? "Unknown"
        let bundleId = activeApp.bundleIdentifier ?? ""

        // Try to get window title using Accessibility API
        var windowTitle: String? = nil
        var permissionGranted = false

        // Use cached permission check to avoid repeated system calls
        if checkPermissionStatus() {
            permissionGranted = true
            windowTitle = getActiveWindowTitle(for: activeApp)

            // Only log if this is a new app without a title (reduce spam)
            if windowTitle == nil && appName != lastTrackedApp {
                print("[TRACKER] No window title available for: \(appName) (app may not expose window titles)")
            }
        } else {
            // Only log permission warning once per tracking session
            if lastTrackedApp == nil {
                print("[TRACKER] ⚠️  Window titles unavailable - Accessibility permissions not granted")
                print("[TRACKER] Please grant Accessibility permission in System Settings")
            }
        }

        // Check if app or window changed
        // IMPORTANT: Always treat window title changes as NEW activities (even within same app)
        // This ensures switching files (e.g., file1.dart -> file2.dart) creates separate work sessions
        let appChanged = appName != lastTrackedApp
        let windowChanged = windowTitle != lastTrackedWindow
        let bundleChanged = bundleId != lastTrackedBundleId

        // Always notify if ANYTHING changed (app, window title, or bundle)
        if appChanged || windowChanged || bundleChanged {
            let titleDisplay = windowTitle ?? "(no title)"
            let permissionStatus = permissionGranted ? "✓" : "✗"

            // Enhanced logging with more details
            if permissionGranted && windowTitle != nil {
                print("[TRACKER] \(permissionStatus) Activity: \(appName) - \(titleDisplay) [\(bundleId)]")
                if !appChanged && windowChanged {
                    print("[TRACKER] → File/Window switched within same app - creating new work session")
                }
            } else if permissionGranted && windowTitle == nil {
                print("[TRACKER] \(permissionStatus) Activity: \(appName) - (no title - app doesn't expose window titles) [\(bundleId)]")
            } else {
                print("[TRACKER] \(permissionStatus) Activity: \(appName) - (no permission) [\(bundleId)]")
            }

            // Always notify about the change to create new work session
            onActivityChange?(appName, windowTitle, bundleId)

            // Update tracking state
            lastTrackedApp = appName
            lastTrackedWindow = windowTitle
            lastTrackedBundleId = bundleId
            lastTrackTime = Date()
        }
    }

    private func getActiveWindowTitle(for app: NSRunningApplication) -> String? {
        guard let pid = app.processIdentifier as pid_t? else {
            return nil
        }

        let application = AXUIElementCreateApplication(pid)
        var value: AnyObject?

        // 1. Try to get the focused window (most reliable for active window)
        var result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        
        if result == .success, let window = value as! AXUIElement? {
            if let title = getWindowTitle(window) {
                return title
            }
        }

        // 2. If no focused window, try to get the main window
        result = AXUIElementCopyAttributeValue(
            application,
            kAXMainWindowAttribute as CFString,
            &value
        )

        if result == .success, let window = value as! AXUIElement? {
            // Verify it's not minimized
            if !isWindowMinimized(window) {
                 if let title = getWindowTitle(window) {
                     return title
                 }
            }
        }

        // 3. Fallback: Iterate through windows to find one that is valid
        // This is needed for some apps that don't set focused/main window correctly
        result = AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        )

        if result == .success, let windows = value as? [AXUIElement] {
            for window in windows {
                // Skip minimized windows
                if isWindowMinimized(window) {
                    continue
                }
                
                // Try to get title
                if let title = getWindowTitle(window) {
                    return title
                }
            }
        }

        return nil
    }
    
    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &value
        )
        
        if result == .success, let minimized = value as? Bool {
            return minimized
        }
        
        return false
    }
    
    private func getWindowTitle(_ window: AXUIElement) -> String? {
        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        if titleResult == .success, let title = titleValue as? String, !title.isEmpty {
            return title
        }
        
        // Try AXTitle as fallback (some apps use this)
        var altTitleValue: AnyObject?
        let altTitleResult = AXUIElementCopyAttributeValue(
            window,
            "AXTitle" as CFString,
            &altTitleValue
        )

        if altTitleResult == .success, let title = altTitleValue as? String, !title.isEmpty {
            return title
        }
        
        return nil
    }

    func getCurrentActivity() -> (appName: String, windowTitle: String?, bundleId: String?)? {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = activeApp.localizedName ?? "Unknown"
        let bundleId = activeApp.bundleIdentifier ?? ""
        var windowTitle: String? = nil

        // Use cached permission check to avoid repeated system calls
        if checkPermissionStatus() {
            windowTitle = getActiveWindowTitle(for: activeApp)
            print("[TRACKER] getCurrentActivity: \(appName) - \(windowTitle ?? "(no title)") [\(bundleId)]")
        } else {
            print("[TRACKER] getCurrentActivity: \(appName) - (no accessibility permission) [\(bundleId)]")
        }

        return (appName, windowTitle, bundleId)
    }

    // MARK: - Public API for Permission Management

    /// Force refresh the permission cache (call this after user grants permissions)
    func refreshPermissionStatus() {
        cachedPermissionStatus = nil
        permissionCheckTime = nil
        let _ = checkPermissionStatus() // Refresh cache
        print("[TRACKER] Permission cache refreshed")
    }
}
