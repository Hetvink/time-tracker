# Auto Check-In/Check-Out Features

This document describes all automatic attendance tracking features in Time Trak.

## Auto Check-In

### How It Works
Time Trak can automatically check you in when the application starts.

### Configuration
You can configure auto check-in in **Settings**:

1. **Auto Check-In** toggle
   - Enable/disable automatic check-in
   - Default: **Enabled**

2. **Only on System Boot** toggle
   - When enabled: Auto check-in ONLY when the computer boots up
   - When disabled: Auto check-in every time the app launches
   - Default: **Enabled** (boot only)

### Behavior
- ✅ **On Boot**: When your computer starts, if auto check-in is enabled, Time Trak will automatically check you in
- ✅ **Prevents Duplicates**: If you're already checked in, auto check-in is skipped
- ✅ **Smart Recovery**: If you had an incomplete session from a crash or power failure, Time Trak will recover it before auto-checking in

### Debug Logs
When auto check-in runs, you'll see detailed logs like:
```
[AUTO CHECK-IN] === Starting Auto Check-In Process ===
[AUTO CHECK-IN] Auto Check-In Enabled: true
[AUTO CHECK-IN] Auto Check-In On Boot Only: true
[AUTO CHECK-IN] Is Boot Event: true
[AUTO CHECK-IN] Current Status: checkedOut
[AUTO CHECK-IN] ✅ All checks passed - proceeding with auto check-in
```

---

## Auto Check-Out

### How It Works
Time Trak automatically checks you out when you shut down your computer or quit the app.

### Behavior
- ✅ **On Shutdown**: When you shut down your computer, Time Trak automatically checks you out
- ✅ **On App Quit**: When you quit Time Trak, it checks you out
- ✅ **Saves Work Time**: All your work time up to the shutdown moment is saved
- ✅ **Handles Breaks**: If you're on break when shutting down, the break is ended and then you're checked out

### Debug Logs
```
[AUTO CHECK-OUT] === Starting Auto Check-Out Process ===
[AUTO CHECK-OUT] Current Status: checkedIn
[AUTO CHECK-OUT] ✅ Proceeding with auto check-out on shutdown
```

---

## Sleep Mode Detection

### How It Works
When your computer goes to sleep or screen locks for a configurable amount of time, Time Trak asks if you were on break.

### Configuration
In **Settings > Break Detection**:

1. **Sleep Threshold** slider
   - Set how long the computer must be asleep before triggering the dialog
   - Range: 1-60 minutes
   - Default: **15 minutes**

### Detection Scenarios
Time Trak detects sleep in these situations:

1. **System Sleep** 🌙
   - When you close your laptop lid
   - When the computer goes to sleep automatically

2. **Screen Lock** 🔒
   - When you lock your screen (Cmd+Ctrl+Q on macOS)
   - When the screen saver with password protection activates

### Break Confirmation Dialog

When the sleep duration exceeds the threshold, you'll see:

**Dialog Title**: "Are you on break?"

**Message**: "Your computer was in sleep mode for [duration]. Were you on a break during this time?"

**Options**:
- **"Yes, I was on break"** - Adds the sleep time as a break period
- **"No, I was working"** - Does nothing, keeps tracking work time

**Features**:
- 🔊 Plays a sound to get your attention
- 🎯 Appears on top of all windows
- ⏱️ **Auto-timeout**: If you don't respond in 30 seconds, defaults to "Yes, I was on break"

### Retroactive Breaks
When you confirm you were on break:
- The sleep time is added as a "retroactive break" to your current session
- The break period shows the exact start and end times
- Your work time is adjusted automatically

### Example Scenario
1. You're working and checked in
2. You close your laptop lid at 2:00 PM
3. You open it again at 2:30 PM (30 minutes later)
4. Since 30 minutes > 15 minutes threshold:
   - Dialog appears: "Are you on break?"
   - "Your computer was in sleep mode for 30 minutes. Were you on a break during this time?"
5. If you click "Yes, I was on break":
   - A 30-minute break from 2:00 PM to 2:30 PM is added to your session
6. If you click "No, I was working":
   - Nothing happens, your work time continues normally

---

## PC Close Auto Check-Out

### How It Works
When you close or shut down your PC, Time Trak automatically checks you out.

### Behavior
- ✅ **Clean Shutdown**: When you properly shut down your PC, Time Trak catches the shutdown event
- ✅ **Forced Shutdown**: If power is lost, Time Trak uses the "last seen" timestamp to determine check-out time
- ✅ **Session Recovery**: On next boot, if there was an incomplete session:
  - Time Trak automatically closes it using the last auto-save timestamp
  - Auto-save happens every 5 minutes while you're checked in

### Session Auto-Save
To protect against power failures:
- Every 5 minutes, Time Trak saves a "last seen" timestamp
- If the app crashes or power is lost, this timestamp is used for recovery
- On next launch, incomplete sessions are automatically closed

---

## Settings Configuration

### Where to Find Settings
1. Click the Time Trak menu bar icon
2. Select "Open Dashboard"
3. Click the ⚙️ Settings tab on the left

### Recommended Settings

**For Remote Workers**:
```
✅ Launch at Login: ON
✅ Auto Check-In: ON
✅ Only on System Boot: ON
   Sleep Threshold: 15 minutes
```

**For Office Workers**:
```
✅ Launch at Login: ON
✅ Auto Check-In: ON
✅ Only on System Boot: ON
   Sleep Threshold: 5-10 minutes
```

**For Contractors (Manual Control)**:
```
❌ Launch at Login: OFF
❌ Auto Check-In: OFF
   Sleep Threshold: 15 minutes
```

---

## Troubleshooting

### Auto Check-In Not Working

**Check these settings**:
1. Go to Settings
2. Ensure "Auto Check-In" is **enabled**
3. Check "Only on System Boot" setting:
   - If ON: Only works when computer boots
   - If OFF: Works every time app launches

**Check system logs**:
```
System event received: boot
[AUTO CHECK-IN] Boot event detected, attempting auto check-in...
[AUTO CHECK-IN] ✅ All checks passed - proceeding with auto check-in
```

### Break Dialog Not Appearing

**Check these**:
1. Go to Settings > Break Detection
2. Check "Sleep Threshold" value
3. Ensure sleep duration exceeded the threshold
4. Look for logs:
   ```
   [WAKE] Sleep duration: 20 minutes
   [WAKE] Threshold: 15 minutes
   [WAKE] Exceeds threshold: true
   [BREAK DIALOG] Showing break confirmation dialog
   ```

### Auto Check-Out Not Working

**This usually means**:
- The app didn't receive the shutdown event
- Check logs for:
  ```
  System event received: shutdown
  [AUTO CHECK-OUT] Shutdown event detected, forcing check-out...
  ```

**Workaround**:
- Next time you launch, Time Trak will automatically recover and close the incomplete session

---

## Technical Details

### Event Sources
Every check-in/check-out has a source:

- `autoSystemStart` - Auto check-in on boot
- `autoSystemShutdown` - Auto check-out on shutdown
- `manualUser` - User manually clicked check-in/out
- `systemRecovery` - Session recovered from crash/power failure
- `autoMidnightTransition` - Session split at midnight

### Session Continuity
Time Trak maintains continuous sessions across:
- ✅ Midnight transitions (auto-splits at 00:00)
- ✅ Crashes (recovery using last-seen timestamp)
- ✅ Multi-day sessions (creates continuation chain)

### Data Safety
- All session data is saved immediately to SQLite database
- Auto-save every 5 minutes protects against crashes
- Session recovery ensures no data is lost

---

## FAQ

**Q: What happens if I manually check in after auto check-in?**
A: Nothing - Time Trak prevents duplicate sessions. You'll stay checked in with the auto check-in timestamp.

**Q: Can I disable auto check-in but keep auto check-out?**
A: Yes! Auto check-out always works regardless of auto check-in settings.

**Q: What if I was on break during sleep but click "No, I was working"?**
A: The system will count it as work time. Be honest for accurate tracking!

**Q: Does the break dialog appear if I'm already checked out?**
A: No - it only appears when you're checked in and working.

**Q: What happens at midnight if I'm still working?**
A: Time Trak automatically:
1. Closes the current day's session at 23:59:59
2. Creates a new session for the next day at 00:00:00
3. Preserves your check-in status (including breaks)

---

## Summary

Time Trak's automatic features ensure:
- ✅ **No manual check-ins needed** (if enabled)
- ✅ **Accurate break tracking** (via sleep detection)
- ✅ **No lost data** (auto-save + recovery)
- ✅ **Clean shutdowns** (auto check-out)
- ✅ **Honest time tracking** (user confirms breaks)

Configure it once in Settings and let Time Trak handle the rest!
