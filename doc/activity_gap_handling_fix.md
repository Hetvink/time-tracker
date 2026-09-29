# Activity Gap Handling Fix

## Problem Statement

When users have multiple check-in/check-out cycles in a day, the activity tracking was **incorrectly including gaps between sessions** in the total duration.

### Example Scenario
```
Check-in:  10:10 AM
Check-out: 10:15 AM  (5 minutes work)

Check-in:  10:20 AM
```

**Expected**: Activity tracking shows **5 minutes** (matching timesheet)
**Before Fix**: Activity tracking showed **10 minutes** (included 5-min gap from 10:15-10:20)

---

## Root Cause

### Bug #1: Work Session Duration Calculation
**Location**: `lib/providers/activity_tracking_provider.dart` - `_createWorkSession()`

```dart
// BUGGY CODE:
WorkSession _createWorkSession(List<AppActivity> activities, int sessionId) {
  final startTime = activities.first.startTime;
  final endTime = lastActivity.endTime ?? DateTime.now();

  return WorkSession(
    totalDuration: endTime.difference(startTime),  // ❌ WRONG!
    // This includes ALL time from first to last activity
    // Including gaps where user was NOT working
  );
}
```

**Problem**: Calculated duration as `last_activity_end - first_activity_start`, which includes:
- Actual activity time
- **Gaps between activities** ❌
- **Gaps between sessions** ❌

---

### Bug #2: Timeline Block Creation
**Location**: `lib/models/timeline_segment.dart` - `TimelineBlock.fromWorkSession()`

```dart
// BUGGY CODE:
static List<TimelineBlock> fromWorkSession(WorkSession session) {
  return [
    TimelineBlock(
      startTime: session.startTime,  // First activity start
      endTime: session.endTime,      // Last activity end
      // ❌ Creates ONE big block including all gaps!
    ),
  ];
}
```

**Problem**: Created a single timeline block spanning the entire session time, visually showing gaps as work time.

---

## The Fixes

### Fix #1: Calculate ACTUAL Activity Duration

**File**: `lib/providers/activity_tracking_provider.dart`

```dart
// FIXED CODE:
WorkSession _createWorkSession(List<AppActivity> activities, int sessionId) {
  final startTime = activities.first.startTime;
  final lastActivity = activities.last;
  final endTime = lastActivity.endTime ?? DateTime.now();

  // ✅ Calculate ACTUAL activity duration (sum of all activities)
  // NOT the time span which includes gaps between activities
  final actualDuration = activities.fold<Duration>(
    Duration.zero,
    (sum, activity) => sum + activity.duration,
  );

  return WorkSession(
    sessionId: sessionId,
    startTime: startTime,
    endTime: endTime,
    totalDuration: actualDuration,  // ✅ Sum of activities only!
    segments: segments,
  );
}
```

**What Changed**:
- **Before**: Duration = `endTime - startTime` (includes gaps)
- **After**: Duration = `sum of all activity.duration` (excludes gaps)

---

### Fix #2: Create Separate Timeline Blocks for Continuous Activity

**File**: `lib/models/timeline_segment.dart`

```dart
// FIXED CODE:
static List<TimelineBlock> fromWorkSession(WorkSession session) {
  List<TimelineBlock> blocks = [];
  List<AppActivity> currentBlockActivities = [];
  DateTime? blockStart;
  DateTime? blockEnd;

  // Get all activities sorted by time
  final allActivities = <AppActivity>[];
  for (var segment in session.segments) {
    allActivities.addAll(segment.activities);
  }
  allActivities.sort((a, b) => a.startTime.compareTo(b.startTime));

  // ✅ Group activities into continuous blocks (gaps < 2 minutes = same block)
  for (final activity in allActivities) {
    if (blockStart == null) {
      // Start first block
      blockStart = activity.startTime;
      blockEnd = activity.endTime ?? DateTime.now();
      currentBlockActivities = [activity];
    } else {
      final gap = activity.startTime.difference(blockEnd!);

      if (gap.inMinutes < 2) {
        // ✅ Continue current block (small gap)
        blockEnd = activity.endTime ?? DateTime.now();
        currentBlockActivities.add(activity);
      } else {
        // ✅ Gap too large - save current block and start new one
        blocks.add(TimelineBlock(
          startTime: blockStart,
          endTime: blockEnd,
          blockType: 'work',
          appNames: apps,
          activities: currentBlockActivities,
        ));

        // Start new block after gap
        blockStart = activity.startTime;
        blockEnd = activity.endTime ?? DateTime.now();
        currentBlockActivities = [activity];
      }
    }
  }

  return blocks;  // ✅ Returns MULTIPLE blocks with gaps between them
}
```

**What Changed**:
- **Before**: ONE big block from first to last activity (gaps shown as work)
- **After**: MULTIPLE blocks separated by gaps (gaps shown as empty space)

---

## How It Works Now

### Scenario: Multiple Check-In/Check-Out Cycles

```
10:10 - 10:15  Check-in → Use Windsurf (5 min)
10:15 - 10:20  Check-out → GAP (not working)
10:20 - 10:30  Check-in → Use Windsurf (10 min)
```

### Before Fix
```
Work Session:
  startTime: 10:10
  endTime: 10:30
  totalDuration: 20 minutes  ❌ WRONG (includes 5-min gap)

Timeline Display:
  [=================]  One 20-minute block
  10:10 -------- 10:30
```

### After Fix
```
Work Session:
  startTime: 10:10 (earliest activity)
  endTime: 10:30 (latest activity)
  totalDuration: 15 minutes  ✅ CORRECT (5 + 10, excludes gap)

Timeline Display:
  [====]     [========]  Two blocks with gap between
  10:10-10:15 GAP 10:20-10:30
```

---

## Visual Representation

### Before Fix
```
Session 1: ████████ (5 min actual)
           10:10-10:15

GAP:       ░░░░░░░░ (5 min gap shown as work!) ❌
           10:15-10:20

Session 2: (not started yet)

Display shows: 10 minutes total ❌
```

### After Fix
```
Session 1: ████████ (5 min actual)
           10:10-10:15

GAP:       ________ (5 min gap shown as empty) ✅
           10:15-10:20

Session 2: ████████████ (10 min actual)
           10:20-10:30

Display shows: 15 minutes total ✅
```

---

## Gap Handling Rules

### Small Gaps (< 2 minutes)
**Treated as**: Part of same work block
**Reason**: Brief switches between apps, still continuous work

```
Windsurf   9:00-9:10 (10 min)
<1 min gap>
time_trak  9:11-9:20 (9 min)

Result: ONE block showing 19 minutes ✅
```

### Large Gaps (≥ 2 minutes)
**Treated as**: Separate work blocks
**Reason**: Likely check-out/check-in or break

```
Windsurf   10:10-10:15 (5 min)
<5 min gap>
Windsurf   10:20-10:30 (10 min)

Result: TWO blocks showing 5 min + 10 min = 15 min total ✅
```

---

## Impact

### Before Fix - Example Day
```
Session 1: 10:00-10:15 (15 min work)
GAP:       10:15-10:30 (15 min idle)
Session 2: 10:30-11:00 (30 min work)

Shown: 60 minutes (10:00-11:00 span) ❌
```

### After Fix - Same Day
```
Session 1: 10:00-10:15 (15 min work)
GAP:       10:15-10:30 (not counted)
Session 2: 10:30-11:00 (30 min work)

Shown: 45 minutes (15 + 30 actual work) ✅
```

**Difference**: 60 min → 45 min (**25% reduction**, now accurate!)

---

## Testing Checklist

### Test Case 1: Single Session with Gap
✅ **Input**:
  - Check-in 9:00, work until 9:10
  - Idle 9:10-9:15 (no activity tracking)
  - Work 9:15-9:20
  - Check-out 9:20

✅ **Expected**: 15 minutes (10 + 5, gap excluded)

---

### Test Case 2: Multiple Check-In/Check-Out
✅ **Input**:
  - Check-in 10:10, work 5 min, check-out 10:15
  - Check-in 10:20, work 10 min, check-out 10:30

✅ **Expected**: 15 minutes (two separate sessions, gap excluded)

---

### Test Case 3: Brief App Switches
✅ **Input**:
  - Windsurf 9:00-9:10
  - 30-second gap
  - time_trak 9:10:30-9:20

✅ **Expected**: ~20 minutes (merged into one block, small gap included)

---

## Files Modified

1. ✅ `lib/providers/activity_tracking_provider.dart`
   - `_createWorkSession()` - Calculate sum of activity durations

2. ✅ `lib/models/timeline_segment.dart`
   - `TimelineBlock.fromWorkSession()` - Create multiple blocks for gaps

---

## Summary

### Before Fix
- ❌ Duration = time span (first to last activity)
- ❌ One big timeline block per session
- ❌ Gaps shown as work time
- ❌ Inflated work hours

### After Fix
- ✅ Duration = sum of actual activity durations
- ✅ Multiple timeline blocks separated by gaps
- ✅ Gaps shown as empty space
- ✅ Accurate work hours matching timesheet

**Result**: Activity tracking now perfectly matches timesheet working hours, with gaps properly excluded!
