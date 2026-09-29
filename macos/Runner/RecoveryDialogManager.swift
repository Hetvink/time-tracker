import Cocoa
import FlutterMacOS

// MARK: - Recovery Dialog Manager
class RecoveryDialogManager {
    private var methodChannel: FlutterMethodChannel?
    private weak var mainFlutterWindow: NSWindow?
    private var isShowingRecoveryDialog: Bool = false
    
    init(methodChannel: FlutterMethodChannel?, mainFlutterWindow: NSWindow?) {
        self.methodChannel = methodChannel
        self.mainFlutterWindow = mainFlutterWindow
    }
    
    func showRecoveryConfirmationAlert(
        checkInTime: Date,
        lastSeenTime: Date?,
        daysMissing: Int
    ) {
        // Prevent duplicate dialogs
        if isShowingRecoveryDialog {
            print("[RECOVERY DIALOG] Already showing - skipping duplicate")
            return
        }
        
        isShowingRecoveryDialog = true
        print("[RECOVERY DIALOG] Showing recovery confirmation dialog")
        print("[RECOVERY DIALOG] Check-in time: \(checkInTime)")
        print("[RECOVERY DIALOG] Last seen time: \(lastSeenTime?.description ?? "none")")
        print("[RECOVERY DIALOG] Days missing: \(daysMissing)")
        
        // Format dates for display
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        let checkInStr = dateFormatter.string(from: checkInTime)
        
        // Build alert message
        let alert = NSAlert()
        alert.messageText = "Session Recovery Required"
        
        var infoText = "You checked in on \(checkInStr).\n\n"
        infoText += "\(daysMissing) day\(daysMissing == 1 ? "" : "s") \(daysMissing == 1 ? "has" : "have") passed since then.\n\n"
        
        if let lastSeen = lastSeenTime {
            let lastSeenStr = dateFormatter.string(from: lastSeen)
            infoText += "Last recorded activity: \(lastSeenStr)\n\n"
        } else {
            infoText += "No activity was recorded after check-in.\n\n"
        }
        
        infoText += "Please choose how to close this session:"
        alert.informativeText = infoText
        
        // Add buttons based on available data
        if lastSeenTime != nil {
            alert.addButton(withTitle: "Use Last Activity Time")
        }
        alert.addButton(withTitle: "Enter Custom Time...")
        alert.addButton(withTitle: "Close at End of Check-in Day")
        
        // Use critical alert style for high visibility
        alert.alertStyle = .critical
        
        // Track if user has responded
        var hasResponded = false
        let responseLock = NSLock()
        
        // Auto-dismiss timer - defaults to "close at end of day" after 30 seconds
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            responseLock.lock()
            defer { responseLock.unlock() }
            
            if !hasResponded {
                hasResponded = true
                print("[RECOVERY DIALOG] Timed out after 30 seconds - defaulting to 'close at end of day'")
                
                // Close the alert window
                DispatchQueue.main.async {
                    NSApp.abortModal()
                }
                
                // Send default response (close at end of day)
                self?.sendRecoveryConfirmation(
                    action: "closeAtEndOfDay",
                    customTime: nil,
                    checkInTime: checkInTime
                )
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
            
            // Set window level to floating BEFORE showing
            alert.window.level = .floating
            
            // Make sure the window moves to the active space and stays on top
            alert.window.collectionBehavior = [.moveToActiveSpace, .transient]
            
            // Force window to front
            alert.window.orderFrontRegardless()
            
            print("[RECOVERY DIALOG] Presenting dialog to user with sound alert and forced activation")
            let response = alert.runModal()
            
            responseLock.lock()
            defer { responseLock.unlock() }
            
            // Only process if we haven't already timed out
            if !hasResponded {
                hasResponded = true
                timer.invalidate()
                
                // Determine which button was clicked
                // Button indices depend on how many buttons we added
                let hasLastSeenButton = lastSeenTime != nil
                
                if response == .alertFirstButtonReturn {
                    if hasLastSeenButton {
                        // "Use Last Activity Time" was clicked
                        print("[RECOVERY DIALOG] User selected: Use Last Activity Time")
                        self?.sendRecoveryConfirmation(
                            action: "useLastSeen",
                            customTime: lastSeenTime,
                            checkInTime: checkInTime
                        )
                    } else {
                        // "Enter Custom Time..." was clicked (no last seen button)
                        print("[RECOVERY DIALOG] User selected: Enter Custom Time")
                        self?.showCustomTimeDialog(checkInTime: checkInTime)
                    }
                } else if response == .alertSecondButtonReturn {
                    if hasLastSeenButton {
                        // "Enter Custom Time..." was clicked
                        print("[RECOVERY DIALOG] User selected: Enter Custom Time")
                        self?.showCustomTimeDialog(checkInTime: checkInTime)
                    } else {
                        // "Close at End of Check-in Day" was clicked (no last seen button)
                        print("[RECOVERY DIALOG] User selected: Close at End of Day")
                        self?.sendRecoveryConfirmation(
                            action: "closeAtEndOfDay",
                            customTime: nil,
                            checkInTime: checkInTime
                        )
                    }
                } else if response == .alertThirdButtonReturn {
                    // "Close at End of Check-in Day" was clicked (has last seen button)
                    print("[RECOVERY DIALOG] User selected: Close at End of Day")
                    self?.sendRecoveryConfirmation(
                        action: "closeAtEndOfDay",
                        customTime: nil,
                        checkInTime: checkInTime
                    )
                }
            } else {
                print("[RECOVERY DIALOG] User responded after timeout - ignoring")
            }
        }
    }
    
    private func showCustomTimeDialog(checkInTime: Date) {
        print("[CUSTOM TIME DIALOG] Showing custom time picker")
        
        // Ensure we're on the main thread with a small delay to let the first dialog close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            let alert = NSAlert()
            alert.messageText = "Enter Checkout Time"
            alert.informativeText = "Please enter the time you actually stopped working.\n\nThis must be after your check-in time and before now."
            
            // Create date picker
            let datePicker = NSDatePicker()
            datePicker.datePickerStyle = .textFieldAndStepper
            datePicker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
            datePicker.dateValue = checkInTime.addingTimeInterval(3600) // Default to 1 hour after check-in
            datePicker.minDate = checkInTime.addingTimeInterval(60) // At least 1 minute after check-in
            datePicker.maxDate = Date() // Cannot be in the future
            datePicker.frame = NSRect(x: 0, y: 0, width: 250, height: 30)
            
            alert.accessoryView = datePicker
            alert.addButton(withTitle: "Confirm")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational
            
            print("[CUSTOM TIME DIALOG] Presenting time picker to user")
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                let selectedTime = datePicker.dateValue
                print("[CUSTOM TIME DIALOG] User selected time: \(selectedTime)")
                
                // Validate the selected time
                if selectedTime <= checkInTime {
                    print("[CUSTOM TIME DIALOG] Invalid time - before check-in")
                    self.showErrorDialog(
                        message: "Invalid Time",
                        info: "Checkout time must be after check-in time."
                    )
                    // Show the dialog again
                    self.showCustomTimeDialog(checkInTime: checkInTime)
                } else if selectedTime > Date() {
                    print("[CUSTOM TIME DIALOG] Invalid time - in the future")
                    self.showErrorDialog(
                        message: "Invalid Time",
                        info: "Checkout time cannot be in the future."
                    )
                    // Show the dialog again
                    self.showCustomTimeDialog(checkInTime: checkInTime)
                } else {
                    // Valid time - send confirmation
                    self.sendRecoveryConfirmation(
                        action: "customTime",
                        customTime: selectedTime,
                        checkInTime: checkInTime
                    )
                }
            } else {
                print("[CUSTOM TIME DIALOG] User cancelled - showing recovery dialog again")
                self.isShowingRecoveryDialog = false
                // Don't show the dialog again automatically - user cancelled
                // Just send default action
                self.sendRecoveryConfirmation(
                    action: "closeAtEndOfDay",
                    customTime: nil,
                    checkInTime: checkInTime
                )
            }
        }
    }
    
    private func showErrorDialog(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        NSSound.beep()
        alert.runModal()
    }
    
    private func sendRecoveryConfirmation(
        action: String,
        customTime: Date?,
        checkInTime: Date
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var args: [String: Any] = [
            "action": action,
            "checkInTime": formatter.string(from: checkInTime)
        ]
        
        if let customTime = customTime {
            args["customTime"] = formatter.string(from: customTime)
        }
        
        print("[RECOVERY DIALOG] Sending confirmation to Flutter: \(action)")
        methodChannel?.invokeMethod("onRecoveryConfirmation", arguments: args)
        
        isShowingRecoveryDialog = false
        print("[RECOVERY DIALOG] Dialog flag reset")
    }
}
