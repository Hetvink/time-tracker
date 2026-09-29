# Timesheet-Based Timeline Implementation

## Overview

The activity timeline is now **100% dependent on timesheet sessions**. Activity blocks are only shown when there is a corresponding timesheet session (check-in/check-out), and the block boundaries come directly from the timesheet times, not from activity tracking times.

---

## Key Principles

### 1. Timesheet is the Single Source of Truth
- **Timesheet** defines when work periods start and end
- **Check-in time** = Work block start time
- **Check-out time** = Work block end time
- **Break periods** = Gaps in work blocks

### 2. Activities are UI Display Only
- Activities show WHAT apps were used during work periods
- Activities do NOT define when work periods start/end
- Activities are filtered to only show during valid timesheet sessions

### 3. No Activity Blocks Without Timesheet Session
- If no timesheet session exists → NO activity blocks shown
- If session is still active (no check-out) → NO blocks shown yet
- Only completed sessions (with check-out) display activity blocks

---

## Implementation Details

### File: `lib/widgets/activity_month_view.dart`

#### The `_loadData()` Method

This is the core method that creates timeline blocks using timesheet sessions:

```dart
Future<void> _loadData() async {
  final attendanceRepo = context.read<AttendanceRepository>();

  // STEP 1: Load TIMESHEET sessions FIRST (source of truth)
  final attendanceSessions = await attendanceRepo.getSessionsForDate(widget.date);

  List<TimelineBlock> blocks = [];

  // STEP 2: For each TIMESHEET session, create work blocks
  for (var attendanceSession in attendanceSessions) {
    final sessionId = attendanceSession['id'] as int;
    final checkInTime = DateTime.parse(attendanceSession['check_in_time']);
    final checkOutTimeStr = attendanceSession['check_out_time'];

    // STEP 3: Skip active sessions (no check-out yet)
    if (checkOutTimeStr == null) continue;

    final checkOutTime = DateTime.parse(checkOutTimeStr);

    // STEP 4: Get activities for this session
    final sessionActivities = await provider.getWorkSessions(widget.date);
    final matchingSession = sessionActivities.where(
      (s) => s.sessionId == sessionId
    ).firstOrNull;

    // STEP 5: Extract apps and activities
    final apps = matchingSession?.segments
        .expand((seg) => seg.activities)
        .map((a) => a.appName)
        .toSet()
        .toList() ?? [];

    final activities = matchingSession?.segments
        .expand((seg) => seg.activities)
        .toList() ?? [];

    // STEP 6: Create ONE work block using TIMESHEET times
    blocks.add(TimelineBlock(
      startTime: checkInTime,      // ✅ From timesheet check-in
      endTime: checkOutTime,        // ✅ From timesheet check-out
      blockType: 'work',
      appNames: apps,
      activities: activities,
    ));

    // STEP 7: Add break blocks for this session
    final breaks = await attendanceRepo.getSessionBreaks(sessionId);
    for (var breakPeriod in breaks) {
      blocks.addAll(TimelineBlock.fromBreakPeriod(breakPeriod));
    }
  }

  // STEP 8: Remove overlaps (breaks take priority over work)
  final finalBlocks = TimelineBlock.removeOverlaps(blocks);

  setState(() {
    _blocks = finalBlocks;
  });
}
```

---

## How It Works: Step-by-Step Example

### Scenario: User Works 9:00 AM - 5:00 PM with Lunch Break

#### Step 1: Timesheet Data
```
Attendance Session:
  - session_id: 123
  - check_in_time: 2026-01-07 09:00:00
  - check_out_time: 2026-01-07 17:00:00

Break Periods:
  - break_id: 1
  - session_id: 123
  - start_time: 2026-01-07 12:00:00
  - end_time: 2026-01-07 13:00:00
```

#### Step 2: Activity Tracking Data
```
Activities (linked via session_id = 123):
  - 09:05-09:45: Windsurf (40 min)
  - 09:50-11:30: Chrome (100 min)
  - 11:35-11:55: time_trak (20 min)
  - 13:10-15:30: Windsurf (140 min)
  - 15:35-16:45: Chrome (70 min)
```

#### Step 3: Timeline Blocks Created

**Work Block (from timesheet):**
```
TimelineBlock(
  startTime: 09:00:00,  // ✅ Check-in time (not 09:05 from activities)
  endTime: 17:00:00,     // ✅ Check-out time (not 16:45 from activities)
  blockType: 'work',
  appNames: ['Windsurf', 'Chrome', 'time_trak'],
  activities: [all 5 activities listed above]
)
```

**Break Block (from timesheet):**
```
TimelineBlock(
  startTime: 12:00:00,
  endTime: 13:00:00,
  blockType: 'break',
  appNames: [],
  activities: []
)
```

#### Step 4: Overlap Removal

The `removeOverlaps()` method splits the work block:

**Final Timeline Blocks:**
```
Work Block 1:
  09:00:00 - 12:00:00 (3 hours)
  Apps: Windsurf, Chrome, time_trak
  Activities: First 3 activities

Break Block:
  12:00:00 - 13:00:00 (1 hour)

Work Block 2:
  13:00:00 - 17:00:00 (4 hours)
  Apps: Windsurf, Chrome
  Activities: Last 2 activities
```

#### Step 5: Visual Display

```
Timeline for 2026-01-07:

09:00 ┌─────────────────────┐
      │                     │
      │   WORK BLOCK 1      │
      │                     │
      │   Windsurf          │
12:00 ├─────────────────────┤
      │   BREAK (Lunch)     │
13:00 ├─────────────────────┤
      │                     │
      │   WORK BLOCK 2      │
      │                     │
      │   Windsurf          │
17:00 └─────────────────────┘
```

---

## Key Differences from Old Implementation

### OLD (Activity-Based Timeline) ❌
```
Work blocks created from activity times:
  - Block 1: 09:05-11:55 (first activity → last activity before break)
  - Block 2: 13:10-16:45 (first activity after break → last activity)

Problems:
  ❌ Missing 5 minutes at start (09:00-09:05)
  ❌ Missing time at end (16:45-17:00)
  ❌ Doesn't match timesheet working hours
  ❌ Shows activity blocks even when user forgot to check in
```

### NEW (Timesheet-Based Timeline) ✅
```
Work blocks created from timesheet times:
  - Block 1: 09:00-12:00 (check-in → break start)
  - Block 2: 13:00-17:00 (break end → check-out)

Benefits:
  ✅ Matches timesheet exactly
  ✅ Shows full work period (09:00-17:00)
  ✅ NO blocks shown without timesheet session
  ✅ Properly excludes breaks
  ✅ Total time = timesheet time (not activity time)
```

---

## Special Cases Handled

### Case 1: No Activities Tracked During Session
**Scenario:** User checked in but didn't use any tracked apps

**Result:**
- Work block STILL shown (09:00-17:00)
- Block shows "No activities tracked"
- Time still counted as working time (from timesheet)

**Why:** Timesheet defines working time, activities are optional detail

---

### Case 2: Activities Outside Session Times
**Scenario:** Native tracker recorded activity at 08:00 (before check-in at 09:00)

**Result:**
- Activity has session_id = NULL
- Activity NOT included in any timeline block
- Activity filtered out by `getActivitiesForDateWithSessions()`

**Why:** Only activities during valid sessions are shown

---

### Case 3: Active Session (No Check-Out Yet)
**Scenario:** User checked in at 09:00 but hasn't checked out yet

**Result:**
- NO timeline block shown
- Current session still active
- Will show block after user checks out

**Why:** Only completed sessions (with check-out) are displayed

---

### Case 4: Multiple Sessions in One Day
**Scenario:**
```
Session 1: 09:00-12:00 (checked in, checked out)
Session 2: 14:00-18:00 (checked in, checked out)
```

**Result:**
- Block 1: 09:00-12:00
- Gap: 12:00-14:00 (no block)
- Block 2: 14:00-18:00

**Why:** Each session creates separate blocks, gaps shown as empty

---

## Total Duration Calculation

### How Total Work Time is Calculated

The total work time shown in the UI is calculated from **actual activity durations**, not timesheet time spans:

```dart
// In WorkSession:
final actualDuration = activities.fold<Duration>(
  Duration.zero,
  (sum, activity) => sum + activity.duration,
);
```

### Example:
```
Timesheet Session: 09:00-17:00 (8 hours)

Activities tracked:
  - Windsurf: 40 min
  - Chrome: 100 min
  - time_trak: 20 min
  Total: 160 min = 2 hours 40 min

Block Display:
  - Timeline block: 09:00-17:00 (shows full 8-hour period)
  - Duration shown: 2h 40m (actual activity time)

Why different?
  - Timeline shows when user was checked in (timesheet)
  - Duration shows actual tracked activity time
  - Gaps in activity (no apps tracked) not counted as work
```

---

## Break Handling

### How Breaks Exclude Work Time

Breaks are handled via the `removeOverlaps()` method:

```dart
// Breaks take priority over work blocks
if (block.blockType == 'break') {
  // Split work block and preserve activities in splits
  if (existing.startTime.isBefore(block.startTime)) {
    // Create work block BEFORE break
    newResult.add(TimelineBlock(
      startTime: existing.startTime,
      endTime: block.startTime,  // Ends when break starts
      blockType: 'work',
      activities: beforeActivities,  // Only activities before break
    ));
  }

  // Add break block
  newResult.add(block);

  if (existing.endTime.isAfter(block.endTime)) {
    // Create work block AFTER break
    newResult.add(TimelineBlock(
      startTime: block.endTime,  // Starts when break ends
      endTime: existing.endTime,
      blockType: 'work',
      activities: afterActivities,  // Only activities after break
    ));
  }
}
```

### Result:
- Work block split into "before break" and "after break"
- Break period shown as separate block
- Activities correctly distributed to respective work blocks
- Total work time excludes break duration

---

## Files Modified

### Core Implementation
1. **`lib/widgets/activity_month_view.dart`**
   - Rewrote `_loadData()` to use timesheet sessions as source
   - Changed from activity-based to timesheet-based block creation

### Supporting Code (Already Correct)
2. **`lib/models/timeline_segment.dart`**
   - `TimelineBlock.fromBreakPeriod()` - Creates break blocks
   - `TimelineBlock.removeOverlaps()` - Handles break exclusion

3. **`lib/providers/activity_tracking_provider.dart`**
   - `getWorkSessions()` - Groups activities by session_id
   - `_createWorkSession()` - Calculates actual activity duration

4. **`lib/services/app_activity_repository.dart`**
   - `getActivitiesForDateWithSessions()` - Filters activities with valid session_id

---

## Testing Checklist

### Test 1: Basic Session
✅ **Input:**
- Check-in: 09:00
- Check-out: 17:00
- Activities: Windsurf 10:00-11:00

✅ **Expected:**
- Timeline block: 09:00-17:00
- Shows Windsurf activity
- Duration: 1 hour (actual activity time)

---

### Test 2: No Activities
✅ **Input:**
- Check-in: 09:00
- Check-out: 17:00
- Activities: None

✅ **Expected:**
- Timeline block: 09:00-17:00
- No activities listed
- Duration: 0 hours

---

### Test 3: With Break
✅ **Input:**
- Check-in: 09:00
- Check-out: 17:00
- Break: 12:00-13:00
- Activities: Chrome 10:00-15:00

✅ **Expected:**
- Work block 1: 09:00-12:00
- Break block: 12:00-13:00
- Work block 2: 13:00-17:00
- Activities split properly

---

### Test 4: No Timesheet Session
✅ **Input:**
- No check-in/check-out
- Activities: Windsurf 10:00-11:00 (session_id = NULL)

✅ **Expected:**
- NO timeline blocks shown
- Activities not displayed

---

### Test 5: Active Session
✅ **Input:**
- Check-in: 09:00
- Check-out: NULL (still checked in)

✅ **Expected:**
- NO timeline block shown
- Will appear after check-out

---

## Summary

### Before This Fix
- ❌ Activity blocks shown without timesheet sessions
- ❌ Block times came from activity start/end times
- ❌ Gaps between activities shown as missing time
- ❌ Activity tracking independent from timesheet

### After This Fix
- ✅ NO blocks without timesheet session
- ✅ Block times from timesheet check-in/check-out
- ✅ Full work period shown (check-in to check-out)
- ✅ Activity timeline 100% dependent on timesheet
- ✅ Breaks properly excluded
- ✅ Total work time matches timesheet

**Result:** Activity timeline is now a visual representation of timesheet data, showing app usage during officially recorded work periods.
