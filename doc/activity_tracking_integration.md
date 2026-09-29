# Activity Tracking Integration with Time Tracking

## Overview

The activity tracking system is now fully integrated with the attendance/time tracking system. Activity tracking automatically starts when you check in and stops when you check out, properly handling breaks and multiple work sessions throughout the day.

## How It Works

### 1. Check-In Flow (Starting Work)
```
User checks in at 10:00 AM
  ↓
Attendance creates session #123
  ↓
Activity tracking starts automatically
  ↓
All activities are tagged with session_id = 123
  ↓
Activities are marked as activityType = 'work'
```

**Example:** You check in at 10:00 AM and start working. Every app you use is tracked and linked to this work session.

---

### 2. Break Flow (Taking a Break)
```
User starts break at 11:00 AM
  ↓
Attendance status changes to 'onBreak'
  ↓
Activity tracking continues (doesn't stop!)
  ↓
All new activities are marked as activityType = 'break'
```

**Example:** At 11:00 AM you take a coffee break. Any apps you use during break time (like browsing social media) are tracked as 'break' activities, not 'work' activities.

---

### 3. End Break Flow (Resuming Work)
```
User ends break at 11:15 AM
  ↓
Attendance status changes back to 'checkedIn'
  ↓
Activity tracking continues
  ↓
All new activities are marked as activityType = 'work'
```

**Example:** You finish your break at 11:15 AM. From this point forward, all activities are tracked as work again.

---

### 4. Check-Out Flow (Ending Work)
```
User checks out at 1:00 PM
  ↓
Attendance closes session #123
  ↓
Activity tracking stops automatically
  ↓
Final activity is ended at 1:00 PM
```

**Example:** You check out at 1:00 PM. All tracking stops and the session is complete.

---

### 5. Multiple Sessions Per Day
```
Session 1: 10:00 AM - 11:00 AM (1 hour work)
  ↓
Computer closed, leave office
  ↓
Session 2: 12:00 PM - 1:00 PM (1 hour work)
```

**Result in UI:**
- Two separate work session blocks are shown
- Session 1: 10:00 AM - 11:00 AM (with all activities from that time)
- Session 2: 12:00 PM - 1:00 PM (with all activities from that time)
- Total tracked time: 2 hours

---

## UI Display

### Activity Timeline View

Each work session is displayed as a separate block showing:

1. **Session Header:**
   - Time range (e.g., "10:00 AM - 1:00 PM")
   - Total duration
   - Number of 15-minute segments
   - Work time vs Break time breakdown (if you took breaks)

2. **15-Minute Segments:**
   - Each segment shows the primary app used during that time
   - Color coding:
     - 🟢 Green = Work activities
     - 🟠 Orange = Break activities
   - Clickable to see detailed app usage within that segment

### Example Display

```
╔═══════════════════════════════════════════════════╗
║ 🔵 Work Session                                   ║
║ 10:00 AM - 1:00 PM • 3h 0m          8 segments   ║
║ 🟢 Work: 2h 45m    🟠 Break: 15m                  ║
╠═══════════════════════════════════════════════════╣
║ 10:00 AM - 10:15 AM | Visual Studio Code    15m  ║
║ 10:15 AM - 10:30 AM | Chrome Browser        15m  ║
║ 10:30 AM - 10:45 AM | Terminal             15m  ║
║ 10:45 AM - 11:00 AM | Visual Studio Code    15m  ║
║ 11:00 AM - 11:15 AM | Instagram (BREAK)    15m  ║
║ 11:15 AM - 11:30 AM | Visual Studio Code    15m  ║
║ 11:30 AM - 12:45 PM | Chrome Browser        15m  ║
║ 12:45 PM - 1:00 PM  | Visual Studio Code    15m  ║
╚═══════════════════════════════════════════════════╝
```

---

## Technical Implementation

### Key Changes Made

1. **Activity Grouping by Session ID**
   - Previously: Grouped activities by 5-minute gaps
   - Now: Grouped by attendance session ID
   - Benefit: Perfect alignment with actual work sessions

2. **Break Time Tracking**
   - Activity tracking continues during breaks
   - Activities are marked with `activityType = 'break'`
   - UI shows break time separately from work time

3. **Integration Service**
   - `TrackingIntegrationService` listens to attendance changes
   - Automatically starts/stops activity tracking
   - Updates activity type based on attendance status

4. **Session Continuity**
   - Each check-in creates a new session ID
   - All activities are linked to that session
   - Multiple sessions per day are properly separated

---

## Testing the System

### Test Scenario 1: Basic Work Session
1. Check in at 10:00 AM
2. Work for 1 hour
3. Check out at 11:00 AM
4. **Expected:** One work session showing 10:00-11:00 AM with all activities marked as 'work'

### Test Scenario 2: Work with Break
1. Check in at 10:00 AM
2. Work until 10:30 AM
3. Take break at 10:30 AM
4. End break at 10:45 AM
5. Work until 11:00 AM
6. Check out at 11:00 AM
7. **Expected:**
   - One session: 10:00-11:00 AM
   - Work time: 45 minutes (10:00-10:30 + 10:45-11:00)
   - Break time: 15 minutes (10:30-10:45)
   - Activities during 10:30-10:45 marked as 'break'

### Test Scenario 3: Multiple Sessions
1. Check in at 10:00 AM
2. Work until 11:00 AM
3. Check out at 11:00 AM
4. Close computer, go to lunch
5. Check in at 12:00 PM
6. Work until 1:00 PM
7. Check out at 1:00 PM
8. **Expected:**
   - Two separate work sessions
   - Session 1: 10:00-11:00 AM (1 hour)
   - Session 2: 12:00-1:00 PM (1 hour)
   - Total tracked time: 2 hours
   - Each session shows its own activities

---

## Benefits

✅ **Accurate Time Tracking**: Activity tracking matches your actual work hours

✅ **Break Time Visibility**: See what you did during breaks vs work time

✅ **Multiple Sessions Support**: Work in different time blocks throughout the day

✅ **Automatic Management**: No manual start/stop of activity tracking needed

✅ **Data Integrity**: All activities linked to proper attendance sessions

---

## Important Notes

1. **Activity tracking starts automatically** when you check in - no need to manually start it

2. **Activity tracking continues during breaks** - this is intentional to track what you do during break time

3. **Activity tracking stops automatically** when you check out

4. **Each check-in creates a new session** - if you check in multiple times per day, you'll see multiple session blocks in the UI

5. **Break activities are clearly marked** - they appear in orange color and are counted separately from work time
