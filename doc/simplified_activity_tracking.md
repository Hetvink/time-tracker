# Simplified Activity Tracking Architecture

## Overview

The activity tracking system has been **SIMPLIFIED** to remove buggy Flutter-side detection logic. The new architecture follows a clear separation:

- **Native Side**: Handles ALL activity detection and tracking
- **Flutter Side**: ONLY displays UI and manages data flow
- **Timesheet**: Source of truth for all time tracking

## Key Principles

### 1. Timesheet is the Source of Truth
- Activities are ONLY shown during timesheet working hours (check-in to check-out)
- Work sessions are based on `attendance_sessions` table
- Break periods come from `session_breaks` table
- No activity tracking when checked out

### 2. Native Tracking Handles Detection
- Native code (macOS/Windows/Linux) tracks active windows and apps
- Native side provides app name, window title, bundle ID
- Flutter receives this data via platform channels
- Flutter does NOT determine activity types

### 3. Flutter is UI Only
- Displays activities from database
- Groups activities by timesheet sessions
- Shows timeline visualizations
- NO complex detection logic

## Data Flow

```
User checks in (Timesheet)
    ↓
TrackingIntegrationService starts native tracking
    ↓
Native code detects app changes → sends to Flutter
    ↓
ActivityTrackingProvider stores in DB with session_id
    ↓
UI queries activities WHERE session_id IS NOT NULL
    ↓
Display ONLY activities during working hours
```

## Key Components

### 1. ActivityTrackingProvider (SIMPLIFIED)
**Purpose**: UI state management and data fetching

**Responsibilities**:
- Start/stop native tracking lifecycle
- Receive activity events from native side
- Store activities with session_id linkage
- Fetch activities for display
- Group activities by session_id

**Does NOT**:
- ❌ Detect activity types
- ❌ Determine work vs break
- ❌ Complex time-gap analysis

### 2. TrackingIntegrationService (SIMPLIFIED)
**Purpose**: Link activity tracking to timesheet

**Responsibilities**:
- Start tracking when checked in
- Stop tracking when checked out
- Update session_id for activities
- Handle midnight transitions

**Does NOT**:
- ❌ Manage activity types
- ❌ Determine break status
- ❌ Complex state management

### 3. AppActivityRepository (ENHANCED)
**Purpose**: Database queries for activities

**Key Method**:
```dart
getActivitiesForDateWithSessions(DateTime date)
  → Returns ONLY activities with session_id IS NOT NULL
  → Ensures only timesheet-linked activities are shown
```

### 4. Timeline Widgets (SIMPLIFIED)
**Purpose**: Display activity blocks

**Work Blocks**:
- Show app usage during check-in periods
- Source: activities from native tracking
- Grouped by attendance session_id

**Break Blocks**:
- Show official breaks
- Source: session_breaks table from timesheet
- Not from activity detection

## Database Linkage

### activities Table
```sql
CREATE TABLE app_activities (
  id INTEGER PRIMARY KEY,
  session_id INTEGER,  -- Links to attendance_sessions
  app_name TEXT,
  window_title TEXT,
  bundle_id TEXT,
  start_time TEXT,
  end_time TEXT,
  duration_seconds INTEGER,
  activity_type TEXT   -- Stored but not determined by Flutter
);
```

### Query Strategy
```dart
// ONLY show activities linked to timesheet
WHERE session_id IS NOT NULL

// Activities without session_id are ignored
// (These would be from tracking while checked out - shouldn't happen)
```

## Activity Display Logic

### Monthly Calendar View
1. Get all attendance sessions for the month
2. For each session, fetch activities by session_id
3. Get session breaks from timesheet
4. Create work blocks from activities
5. Create break blocks from timesheet breaks
6. Display both on timeline

### Work Sessions with Segments
1. Query activities for date with session_id
2. Group by session_id (one session = one attendance period)
3. Divide each session into 15-minute segments
4. Show most-used app per segment
5. All based on timesheet boundaries

## Benefits of Simplified Approach

### ✅ Reliability
- No complex detection logic to break
- Timesheet is single source of truth
- Native tracking is stable and proven

### ✅ Accuracy
- Activities shown ONLY during working hours
- No guessing about work vs break
- Exact match with timesheet records

### ✅ Maintainability
- Flutter code is simple data display
- Easy to understand and debug
- Clear separation of concerns

### ✅ Performance
- Simple database queries
- No complex calculations in Flutter
- Efficient data fetching

## Migration from Old System

### Removed Components
- ❌ Complex activity type determination in Flutter
- ❌ `_determineActivityType()` method
- ❌ `setAttendanceStatus()` method
- ❌ Time-gap based session detection
- ❌ Flutter-side break detection

### Simplified Components
- ✅ `_recordActivity()` - just stores data
- ✅ `_groupIntoSessionsBySessionId()` - simple grouping
- ✅ Timeline rendering - displays database records
- ✅ Integration service - basic start/stop

## Testing Strategy

### What to Test
1. Activities appear ONLY during check-in periods
2. Activities have correct session_id
3. Timeline shows work blocks for activities
4. Timeline shows break blocks from timesheet
5. No activities shown when checked out

### What NOT to Test
- ❌ Activity type detection (not our job)
- ❌ Complex time calculations (simplified)
- ❌ Break detection logic (uses timesheet)

## Future Enhancements

If activity type needs to be determined:
1. **Option A**: Native side determines it (recommended)
2. **Option B**: Database trigger based on attendance state
3. **Option C**: Query-time join with attendance sessions

Do NOT add complex detection logic back into Flutter providers!

## Summary

The new simplified system:
- Native tracking → provides app data
- Flutter → stores with session_id
- Database → links to timesheet
- UI → displays ONLY timesheet-linked activities
- Timesheet → source of truth for everything

**Keep it simple. Let the timesheet lead. Native tracks. Flutter displays.**
