# Activity Tracking Feature

## Overview

The Activity Tracking feature automatically monitors which applications and windows you're using throughout your work day, providing detailed insights into how you spend your time. This feature integrates seamlessly with the existing attendance system.

## Features

### 1. Automatic Window/Application Tracking
- Tracks active application name every 5 seconds
- Records window titles for better context
- Captures bundle IDs for precise app identification
- Runs automatically when you're checked in

### 2. Visual Timeline View
- Calendar-style timeline showing your entire day
- Time slots from 12 AM to 12 PM displayed on the left
- Color-coded activity blocks:
  - **Green**: Work-related applications (code editors, terminals, development tools)
  - **Yellow/Orange**: Break-related applications (chat, social media, entertainment)
  - **Gray**: Idle or unknown activities

### 3. Activity Statistics
- Top applications by usage time
- Total work time vs break time
- Percentage breakdown of time spent in each app
- Activity count for the day

### 4. Smart Activity Classification
The system automatically categorizes applications:

**Work Applications:**
- Visual Studio Code
- Xcode
- Terminal/iTerm
- IntelliJ IDEA, Android Studio
- WebStorm, PyCharm
- Postman, Docker
- Browsers (when used for development)

**Break Applications:**
- Slack, Discord
- WhatsApp, Telegram, Messages
- Music, Spotify
- YouTube

## How It Works

### Architecture

1. **Native macOS Tracker** ([ActiveWindowTracker.swift](../macos/Runner/ActiveWindowTracker.swift))
   - Uses Accessibility API to detect active windows
   - Polls every 5 seconds for changes
   - Reports changes to Flutter via platform channels

2. **Database Schema** (`app_activities` table)
   ```sql
   CREATE TABLE app_activities (
     id INTEGER PRIMARY KEY,
     session_id INTEGER,
     app_name TEXT NOT NULL,
     window_title TEXT,
     bundle_id TEXT,
     start_time TEXT NOT NULL,
     end_time TEXT,
     duration_seconds INTEGER,
     start_time_utc TEXT NOT NULL,
     end_time_utc TEXT,
     activity_type TEXT DEFAULT 'work'
   )
   ```

3. **Flutter Components**
   - **ActivityTrackingProvider**: Manages tracking state and data
   - **AppActivityRepository**: Database operations
   - **ActivityTimeline Widget**: Visual timeline rendering
   - **ActivityTrackingPage**: Main UI for viewing tracked activities

### Integration with Attendance System

The tracking automatically:
- **Starts** when you check in
- **Stops** when you check out
- **Continues** during breaks (but marks activities appropriately)
- **Links** activities to your current session

## Usage

### Viewing Your Activity Timeline

1. Click "Activity Timeline" in the sidebar
2. Select a date using the date picker
3. View your activities in the timeline
4. Check the sidebar for top applications

### Date Navigation

- **Previous Day**: Click the left arrow (◀)
- **Next Day**: Click the right arrow (▶)
- **Jump to Date**: Click on the date to open date picker
- **Today**: Click the "Today" button

### Understanding the Timeline

- **Vertical Axis**: Time of day (hours)
- **Blocks**: Each colored block represents time spent in an application
- **Block Size**: Height indicates duration
- **Block Color**: Indicates activity type (work/break)
- **Hover**: (Future) Show detailed information

## Permissions Required

### macOS Accessibility Permission

The app needs Accessibility permissions to track active windows:

1. macOS will prompt for permission on first run
2. If not prompted, go to: **System Settings → Privacy & Security → Accessibility**
3. Add "Time Trak" to the allowed applications
4. Toggle it ON

**Why needed**: To read which application and window is currently active.

## Privacy & Data

### What is tracked:
- Application names (e.g., "Visual Studio Code")
- Window titles (e.g., "main.dart - time_trak")
- Bundle identifiers (e.g., "com.microsoft.VSCode")
- Timestamps (when you switched to the app)
- Duration (how long you used the app)

### What is NOT tracked:
- Keyboard input
- Mouse movements
- Screen content or screenshots
- File contents
- Network activity

### Data Storage:
- All data is stored **locally** on your device
- Stored in SQLite database: `~/Documents/attendance_tracker.db`
- No data is sent to external servers
- You have full control to delete all data via Settings

## Customization

### Activity Type Classification

You can customize how apps are classified by editing:
`lib/providers/activity_tracking_provider.dart`

Look for the `_determineActivityType()` method:

```dart
String _determineActivityType(String appName, String? bundleId) {
  final workApps = [
    'Visual Studio Code',
    'Xcode',
    // Add more apps here
  ];

  final breakApps = [
    'Slack',
    'Discord',
    // Add more apps here
  ];

  // Classification logic
}
```

### Tracking Interval

To change how often the app checks for window changes, edit:
`macos/Runner/ActiveWindowTracker.swift`

```swift
private let trackingInterval: TimeInterval = 5.0 // seconds
```

## Troubleshooting

### Activity Tracking Not Working

1. **Check Accessibility Permissions**
   - Go to System Settings → Privacy & Security → Accessibility
   - Ensure Time Trak is enabled

2. **Restart the App**
   - Quit Time Trak completely
   - Reopen it

3. **Check if Checked In**
   - Activity tracking only works when you're checked in
   - Click "Check In" on the Dashboard

### No Activities Showing

1. **Verify the date**
   - Make sure you're viewing the correct date
   - Click "Today" to jump to today's activities

2. **Check if tracking was enabled**
   - Tracking only works after implementing this feature
   - Historical data before this feature won't exist

3. **Database issues**
   - Check console for errors
   - Try refreshing the page

### Performance Issues

If the app feels slow:

1. **Reduce tracking frequency**
   - Increase `trackingInterval` from 5 to 10 seconds

2. **Clean old data**
   - Use Settings → Clear All Data (this will delete everything)
   - Or manually delete old activities from database

## API Reference

### ActivityTrackingProvider

```dart
// Start tracking
provider.startTracking(sessionId: currentSessionId);

// Stop tracking
provider.stopTracking();

// Get daily activity
final daily = await provider.getDailyActivity(date);

// Get timeline blocks
final blocks = await provider.getTimelineBlocks(date);
```

### AppActivityRepository

```dart
// Insert new activity
final id = await repository.insertActivity(activity);

// End current activity
await repository.endActivity(id, DateTime.now());

// Get activities for a date
final activities = await repository.getActivitiesForDate(date);

// Get app usage statistics
final usage = await repository.getAppUsageForDate(date);
```

## Future Enhancements

Potential improvements:
- Screenshots at intervals
- Productivity score calculation
- Weekly/monthly reports
- Export to CSV/PDF
- Custom app categories
- Idle time detection
- Focus mode (pause tracking)
- Integration with calendar apps
- AI-powered insights

## Technical Details

### Database Migration

The feature adds a new table via migration (version 4):
- See: `lib/services/database_service.dart`
- Table: `app_activities`
- Indexes on: session_id, start_time, app_name

### Platform Channels

New methods added to `com.attendance.tracker/system` channel:
- `startActivityTracking`: Begin tracking
- `stopActivityTracking`: Stop tracking
- `getCurrentActivity`: Get current app/window
- `onActivityChange`: Event when activity changes

### Files Added

1. **Models**
   - `lib/models/app_activity.dart`

2. **Services**
   - `lib/services/app_activity_repository.dart`
   - `lib/services/tracking_integration_service.dart`

3. **Providers**
   - `lib/providers/activity_tracking_provider.dart`

4. **UI**
   - `lib/widgets/activity_timeline.dart`
   - `lib/pages/activity_tracking_page.dart`

5. **Native**
   - `macos/Runner/ActiveWindowTracker.swift`

### Files Modified

1. `lib/main.dart` - Added providers and navigation
2. `lib/widgets/macos_shell.dart` - Added sidebar item
3. `lib/services/database_service.dart` - Database migration
4. `lib/services/platform_channel_service.dart` - New channels
5. `macos/Runner/AppDelegate.swift` - Integration with tracker
6. `macos/Runner/Info.plist` - Accessibility permission description

## Support

For issues or questions:
- Check the console for error messages
- Review this documentation
- Check code comments in the source files
