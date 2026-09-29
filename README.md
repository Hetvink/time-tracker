# Time Trak - Employee Activity & Attendance Tracking System

A sophisticated cross-platform Flutter application for employee time tracking, activity monitoring, and attendance management with real-time synchronization and admin dashboards.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Data Flow](#data-flow)
- [Setup Instructions](#setup-instructions)
- [Platform Configuration](#platform-configuration)
- [Development Guide](#development-guide)
- [API Documentation](#api-documentation)
- [Troubleshooting](#troubleshooting)

---

## Overview

**Time Trak** is a comprehensive employee activity tracking and attendance management system designed for desktop (macOS, Windows) and web platforms. It features:

- Real-time activity monitoring with native platform integration
- Automatic session recovery after system crashes/power failures
- Offline-first architecture with background synchronization
- Admin dashboard with user impersonation and detailed analytics
- OAuth 2.0 authentication with Google Sign-In
- SQLite local storage with Supabase cloud synchronization

---

## Features

### Core Features

#### 1. Authentication & Authorization
- **OAuth 2.0 Integration** with Google Sign-In
  - PKCE flow for desktop (localhost callback server)
  - Implicit flow for web (popup-based)
- **Session Persistence** with automatic restoration
- **Role-Based Access Control** (Admin / Member)
- **Token Management** with SharedPreferences storage

#### 2. Activity Tracking
- **Native Window Monitoring**
  - macOS: Accessibility API for active window tracking
  - Windows: Win32 API for foreground application monitoring
- **Real-time Activity Capture**
  - App name, window title, bundle ID
  - Timestamp tracking with session linkage
- **Activity History** with filtering and search
- **Automatic Activity Closure** on session end

#### 3. Attendance Management
- **Session Tracking**
  - Check-in / Check-out with manual and automatic modes
  - Break management (start/end with notes)
  - Duration calculations (work time, break time, total time)
- **Event Sources**
  - Manual user actions
  - Auto system start (boot/wake detection)
  - Auto system shutdown (sleep detection)
  - System recovery (power failure recovery)
  - Midnight transitions (24-hour session splits)
- **Session Recovery**
  - Last-seen timestamp tracking
  - Recovery dialog with multiple options
  - Session continuation tracking
- **Timezone Handling**
  - Local and UTC timestamps stored separately
  - Automatic DST handling

#### 4. Timesheet Management
- **Daily Timesheet**
  - Session breakdown by day
  - Work/break time visualization
  - Session card with activity details
- **Monthly Timesheet**
  - Aggregated monthly metrics
  - Daily summaries with graphs
  - Export capabilities
- **Live Performance Metrics**
  - Real-time duration updates
  - Performance indicators
  - Break compliance tracking

#### 5. Admin Features
- **User Management Dashboard**
  - List all users with activity status
  - User detail pages with session history
  - Activity timeline visualization
- **User Impersonation**
  - Admin can view data as any user
  - Testing and debugging support
- **Analytics & Reports**
  - Day/Month/Timeline views per user
  - Activity distribution analysis
  - Attendance pattern insights

#### 6. Platform-Specific Features

**Desktop (macOS/Windows)**
- System tray integration
- Background activity tracking
- Native dialogs and notifications
- Auto-start on system boot
- Power state monitoring (sleep/wake)
- Window management (minimize to tray)

**Web**
- Read-only dashboard
- OAuth popup handling
- Responsive layout
- Real-time updates from Supabase

---

## Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter UI Layer                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐ │
│  │ Pages    │  │ Widgets  │  │ Providers│  │ Theme/Routing  │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────────────┘ │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│                    Business Logic Layer                         │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │ Auth Service │  │ Attendance   │  │ Activity Tracking  │   │
│  │              │  │ Repository   │  │ Service            │   │
│  └──────────────┘  └──────────────┘  └────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Supabase Sync Service (Bidirectional)            │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
┌────────▼────────┐            ┌─────────▼────────┐
│  Local Storage  │            │   Supabase Cloud │
│  (SQLite FFI)   │◄──────────►│   (PostgreSQL)   │
│                 │   Sync     │                  │
│  - Sessions     │            │  - Sessions      │
│  - Activities   │            │  - Activities    │
│  - Breaks       │            │  - Users         │
│  - Users Cache  │            │  - Auth          │
└────────┬────────┘            └──────────────────┘
         │
┌────────▼────────┐
│  Native Layer   │
│  (Swift/C++)    │
│                 │
│  - Window Track │
│  - Power Monitor│
│  - System Tray  │
│  - Auto-Start   │
└─────────────────┘
```

### Data Flow Architecture

#### Offline-First Pattern

```
User Action (Check-in)
    ↓
AttendanceProvider (State Management)
    ↓
AttendanceRepository (SQLite Write)
    ↓
SyncedAttendanceRepository (Queue Sync)
    ↓
SupabaseSyncService (Background Upload)
    ↓
Supabase Cloud (Persistent Storage)
    ↓
Other Clients (Real-time Updates)
```

#### Activity Tracking Pipeline

```
Native OS Event (Window Change)
    ↓
Platform Channel (Method Channel Bridge)
    ↓
PlatformChannelService (Event Router)
    ↓
ActivityTrackingProvider (State Handler)
    ↓
AppActivityRepository (SQLite Write)
    ↓
Sync Service (Background Upload)
    ↓
Supabase (Cloud Storage)
    ↓
UI Update (ChangeNotifier)
```

### Session Recovery Flow

```
System Boot/Wake Event
    ↓
Native Power Monitor Detects
    ↓
Platform Channel → Flutter
    ↓
AttendanceProvider._handleBoot()
    ↓
Check for Unclosed Sessions (last_seen_time)
    ↓
┌─────────────────────┐
│ Gap > Threshold?    │
└─────┬───────────────┘
      │ YES
      ▼
Show Recovery Dialog
├─ Use Last Seen Time
├─ Enter Custom Time
└─ Close Now
      │
      ▼
Update Session (check_out_time)
      ↓
Sync to Supabase
      ↓
UI Refresh
```

---

## Tech Stack

### Frontend
- **Flutter** (v3.10.1+) - Cross-platform UI framework
- **Provider** (v6.1.2) - State management
- **Material Design** - UI components

### Backend
- **Supabase**
  - PostgreSQL database
  - Authentication (OAuth 2.0)
  - Real-time subscriptions
  - RESTful API

### Local Storage
- **SQLite** (sqflite_common_ffi) - Offline-first local database

### Platform-Specific
- **macOS**: Swift (AppDelegate, Window/Power monitoring)
- **Windows**: C++ (Win32 API, System tray)

### Additional Libraries
- **URL Launcher** - Deep linking
- **Shared Preferences** - Settings persistence
- **Window Manager** (v0.5.1) - Desktop window control
- **Tray Manager** (v0.5.2) - System tray integration
- **Flutter DotEnv** - Environment configuration

---

## Project Structure

```
time_trak/
├── lib/
│   ├── main.dart                    # Entry point (platform detection)
│   ├── main_desktop.dart            # Desktop entry point
│   ├── main_web.dart                # Web entry point
│   │
│   ├── config/                      # Configuration
│   │   ├── supabase_config.dart     # Supabase initialization
│   │   ├── platform_config.dart     # Platform detection
│   │   └── web_env_config.dart      # Web environment
│   │
│   ├── models/                      # Data models
│   │   ├── attendance_state.dart    # Session state & enums
│   │   ├── app_activity.dart        # Activity model
│   │   ├── work_session.dart        # Session model
│   │   ├── daily_timesheet.dart     # Timesheet model
│   │   └── user_role.dart           # User roles enum
│   │
│   ├── services/                    # Business logic (8626 LOC)
│   │   ├── auth_service.dart                    # OAuth authentication
│   │   ├── attendance_repository.dart           # SQLite attendance CRUD
│   │   ├── supabase_sync_service.dart           # Sync engine
│   │   ├── web_attendance_repository.dart       # Web wrapper
│   │   ├── app_activity_repository.dart         # Activity tracking
│   │   ├── database_service.dart                # SQLite initialization
│   │   ├── platform_channel_service.dart        # Native communication
│   │   ├── user_repository.dart                 # User management
│   │   ├── admin_repository.dart                # Admin queries
│   │   ├── tracking_integration_service.dart    # Lifecycle coordination
│   │   ├── session_persistence_service.dart     # Session save/restore
│   │   └── crash_reporting_service.dart         # Error reporting
│   │
│   ├── providers/                   # State management
│   │   ├── attendance_provider.dart             # Session state
│   │   ├── activity_tracking_provider.dart      # Activity state
│   │   ├── auth_provider.dart                   # Auth state
│   │   ├── timesheet_provider.dart              # Timesheet logic
│   │   ├── admin_dashboard_provider.dart        # Admin state
│   │   └── navigation_provider.dart             # Navigation state
│   │
│   ├── pages/                       # UI screens
│   │   ├── desktop/
│   │   │   └── desktop_dashboard_page.dart      # Main desktop UI
│   │   ├── web/
│   │   │   └── web_dashboard_page.dart          # Web dashboard
│   │   ├── admin/
│   │   │   ├── admin_dashboard_page.dart        # User list
│   │   │   └── user_detail_page.dart            # User details
│   │   ├── auth/
│   │   │   └── login_page.dart                  # OAuth login
│   │   ├── activity_tracking_page.dart          # Activity view
│   │   ├── timesheet_page.dart                  # Daily timesheet
│   │   ├── monthly_timesheet_page.dart          # Monthly view
│   │   └── settings_page.dart                   # Settings
│   │
│   ├── widgets/                     # Reusable UI components
│   │   ├── dashboard_timer.dart                 # Live timer widget
│   │   ├── session_card.dart                    # Session display
│   │   ├── daily_timesheet_table.dart           # Timesheet table
│   │   ├── live_timesheet_summary.dart          # Live metrics
│   │   ├── monthly_timesheet_summary.dart       # Monthly summary
│   │   ├── session_timeline_widget.dart         # Timeline visualization
│   │   ├── macos_shell.dart                     # macOS navigation shell
│   │   └── [Additional widgets]
│   │
│   ├── infrastructure/              # Data access layer
│   │   └── supabase/
│   │       └── repositories/
│   │           ├── supabase_session_repository.dart    # Read-only sessions
│   │           ├── supabase_activity_repository.dart   # Read-only activities
│   │           └── supabase_user_repository.dart       # User queries
│   │
│   ├── theme/
│   │   └── macos_theme.dart         # Dark theme configuration
│   │
│   └── utils/
│       ├── logger.dart              # Logging utility
│       └── web_oauth_popup.dart     # Web OAuth handler
│
├── macos/                           # macOS native code
│   ├── Runner/
│   │   ├── AppDelegate.swift        # Main app delegate
│   │   ├── ActiveWindowTracker.swift # Window monitoring
│   │   └── RecoveryDialogManager.swift # Recovery dialogs
│   └── Podfile                      # CocoaPods dependencies
│
├── windows/                         # Windows native code
│   ├── runner/
│   │   ├── flutter_window.cpp       # Main window
│   │   ├── main.cpp                 # Entry point
│   │   ├── power_monitor.cpp/h      # Power state monitoring
│   │   └── [Additional C++ files]
│   └── CMakeLists.txt               # Build configuration
│
├── supabase/                        # Supabase configuration
│   └── [Schema and function files]
│
├── pubspec.yaml                     # Flutter dependencies
├── .env.example                     # Environment template
└── README.md                        # This file
```

---

## Data Flow

### 1. Authentication Flow

#### Desktop OAuth (PKCE)
```
User Clicks "Sign in with Google"
    ↓
AuthService.signInWithGoogle() triggered
    ↓
Supabase.signInWithOAuth() opens system browser
    ↓
User authenticates on Google
    ↓
OAuth server redirects to http://localhost:3000?code=XXX
    ↓
LocalhostServerService intercepts request
    ↓
Code exchanged for token (PKCE code_verifier)
    ↓
Token stored in SharedPreferences
    ↓
Session object persisted via SessionPersistenceService
    ↓
User logged in → Navigate to Dashboard
```

#### Web OAuth (Implicit)
```
User Clicks "Sign in with Google"
    ↓
web_oauth_popup.dart opens popup window
    ↓
Popup navigates to Supabase OAuth URL
    ↓
User authenticates on Google
    ↓
OAuth redirects to app URL with #access_token=XXX
    ↓
Popup extracts token from URL fragment
    ↓
postMessage sends token to parent window
    ↓
Token stored in localStorage
    ↓
User logged in → Dashboard rendered
```

### 2. Check-In/Check-Out Flow

```
┌────────────────────────────────────────────────────────────────┐
│                      User Clicks "Check In"                     │
└───────────────────────────────┬────────────────────────────────┘
                                │
                                ▼
                    AttendanceProvider.checkIn()
                                │
                                ▼
        AttendanceRepository.createSession(EventSource.manualUser)
                                │
                                ▼
        ┌─────────────────────────────────────────────┐
        │  SQLite: INSERT INTO attendance_sessions    │
        │  - user_id, check_in_time (local + UTC)     │
        │  - is_closed = false, last_seen_time = now  │
        └─────────────────────┬───────────────────────┘
                              │
                              ▼
            SyncedAttendanceRepository: Queue sync job
                              │
                              ▼
            SupabaseSyncService.syncAttendanceSession('insert')
                              │
                              ▼
            Supabase: INSERT to attendance_sessions table
                              │
                              ▼
            Update synced_at timestamp in SQLite
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  UI Updates (via ChangeNotifier)            │
        │  - Status badge: "Checked Out" → "Working"  │
        │  - Timer starts counting up                 │
        │  - Session card appears                     │
        └─────────────────────────────────────────────┘
```

### 3. Activity Tracking Flow

```
User Switches from Chrome to Excel
    ↓
┌───────────────────────────────────────┐
│  Native Layer (macOS/Windows)         │
│  - Detects foreground window change   │
│  - Extracts: App name, Window title   │
│  - Previous activity duration calc    │
└──────────────┬────────────────────────┘
               │
               ▼ (Platform Channel)
┌──────────────────────────────────────┐
│  PlatformChannelService              │
│  - Receives ActivityChangeEvent      │
│  - Broadcasts to listeners           │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  ActivityTrackingProvider            │
│  - _handleActivityChange()           │
│  - Closes previous activity          │
│  - Links to current session          │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  AppActivityRepository               │
│  - SQLite INSERT: app_activities     │
│  - Fields: session_id, app_name,     │
│    window_title, timestamp           │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  Sync Service (Background)           │
│  - Queue sync job                    │
│  - Upload to Supabase                │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  UI Update                           │
│  - Activity widget shows:            │
│    "Excel - Monthly Report.xlsx"     │
│  - Timeline updates with new entry   │
└──────────────────────────────────────┘
```

### 4. Session Recovery Flow

```
System Crashes or Power Failure
    ↓
(last_seen_time continues in DB without update)
    ↓
User Restarts Computer
    ↓
Time Trak Auto-Starts
    ↓
┌──────────────────────────────────────────┐
│  Native PowerMonitor Detects Boot Event  │
└──────────────┬───────────────────────────┘
               │
               ▼
    Platform Channel → Flutter
               │
               ▼
┌──────────────────────────────────────────┐
│  AttendanceProvider._handleBoot()        │
│  - Queries unclosed sessions             │
│  - Calculates gap: now - last_seen_time  │
└──────────────┬───────────────────────────┘
               │
         ┌─────▼─────┐
         │ Gap > 15m? │
         └─────┬─────┘
               │ YES
               ▼
┌──────────────────────────────────────────┐
│  Show Recovery Dialog (Native)           │
│  "Session was open during shutdown"      │
│                                           │
│  Options:                                 │
│  ○ Use Last Seen Time (2:30 PM)          │
│  ○ Enter Custom Time                     │
│  ○ Close Now                             │
│                                           │
│  [Cancel]  [Confirm]                     │
└──────────────┬───────────────────────────┘
               │
               ▼
    User Selects "Use Last Seen Time"
               │
               ▼
┌──────────────────────────────────────────┐
│  AttendanceRepository.updateSession()    │
│  - Set check_out_time = last_seen_time   │
│  - Set is_closed = true                  │
│  - Set event_source = systemRecovery     │
└──────────────┬───────────────────────────┘
               │
               ▼
    Sync to Supabase
               │
               ▼
    UI Refreshes (Session Closed)
```

### 5. Midnight Transition Flow

```
23:59:59 → 00:00:00 (Day Change)
    ↓
AttendanceProvider Timer Detects Midnight
    ↓
┌──────────────────────────────────────────┐
│  _checkMidnightTransition()              │
│  - Current session open?                 │
│  - Date changed?                         │
└──────────────┬───────────────────────────┘
               │ YES
               ▼
┌──────────────────────────────────────────┐
│  Close Current Session at 23:59:59       │
│  - check_out_time = 2024-01-15 23:59:59  │
│  - event_source = autoMidnightTransition │
│  - is_closed = true                      │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Create New Session at 00:00:00          │
│  - check_in_time = 2024-01-16 00:00:00   │
│  - continuation_of_session_id = prev_id  │
│  - event_source = autoMidnightTransition │
└──────────────┬───────────────────────────┘
               │
               ▼
    Sync Both Sessions to Supabase
               │
               ▼
    UI Updates (New Session Card for New Day)
```

### 6. Break Management Flow

```
User Clicks "Start Break"
    ↓
AttendanceProvider.startBreak()
    ↓
┌──────────────────────────────────────────┐
│  Validation                              │
│  - Is user checked in?                   │
│  - No existing active break?             │
└──────────────┬───────────────────────────┘
               │ VALID
               ▼
┌──────────────────────────────────────────┐
│  AttendanceRepository.startBreak()       │
│  - SQLite INSERT: break_periods          │
│  - session_id (current session)          │
│  - break_start_time (local + UTC)        │
│  - break_end_time = NULL                 │
└──────────────┬───────────────────────────┘
               │
               ▼
    Sync to Supabase
               │
               ▼
┌──────────────────────────────────────────┐
│  UI Update                               │
│  - Status: "Working" → "On Break"        │
│  - Break timer starts                    │
│  - Activity tracking pauses              │
└──────────────────────────────────────────┘

    ... User returns from break ...

User Clicks "End Break"
    ↓
AttendanceProvider.endBreak()
    ↓
┌──────────────────────────────────────────┐
│  AttendanceRepository.endBreak()         │
│  - UPDATE break_periods                  │
│  - break_end_time = now                  │
│  - duration_seconds = end - start        │
└──────────────┬───────────────────────────┘
               │
               ▼
    Sync to Supabase
               │
               ▼
┌──────────────────────────────────────────┐
│  UI Update                               │
│  - Status: "On Break" → "Working"        │
│  - Break duration added to session card  │
│  - Activity tracking resumes             │
└──────────────────────────────────────────┘
```

---

## Setup Instructions

### Prerequisites

- **Flutter SDK**: v3.10.1 or higher
- **Dart SDK**: v3.0.0 or higher
- **Xcode**: v14.0+ (for macOS development)
- **Visual Studio**: 2022+ (for Windows development)
- **Supabase Account**: Free tier or higher
- **Google OAuth Credentials**: Client ID and secret

### 1. Clone the Repository

```bash
git clone https://github.com/hetvink/time-tracker.git
cd time_trak
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure Environment Variables

Create a `.env` file in the project root:

```bash
cp .env.example .env
```

Edit `.env` with your credentials:

```env
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here

# OAuth Configuration
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret

# Platform-Specific
LOCALHOST_SERVER_PORT=3000
```

### 4. Supabase Setup

#### Create Tables

Run the SQL schema in your Supabase SQL editor:

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  created_at TIMESTAMPTZ DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT true
);

-- Attendance sessions table
CREATE TABLE attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) NOT NULL,
  check_in_time TIMESTAMP NOT NULL,
  check_in_time_utc TIMESTAMPTZ NOT NULL,
  check_out_time TIMESTAMP,
  check_out_time_utc TIMESTAMPTZ,
  is_closed BOOLEAN DEFAULT false,
  is_deleted BOOLEAN DEFAULT false,
  last_seen_time TIMESTAMPTZ,
  continuation_of_session_id UUID REFERENCES attendance_sessions(id),
  event_source TEXT CHECK (event_source IN (
    'autoSystemStart',
    'autoSystemShutdown',
    'manualUser',
    'systemRecovery',
    'autoMidnightTransition'
  )),
  created_at TIMESTAMPTZ DEFAULT now(),
  synced_at TIMESTAMPTZ
);

-- Break periods table
CREATE TABLE break_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES attendance_sessions(id) NOT NULL,
  break_start_time TIMESTAMP NOT NULL,
  break_start_time_utc TIMESTAMPTZ NOT NULL,
  break_end_time TIMESTAMP,
  break_end_time_utc TIMESTAMPTZ,
  duration_seconds INT,
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- App activities table
CREATE TABLE app_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES attendance_sessions(id) NOT NULL,
  app_name TEXT NOT NULL,
  window_title TEXT,
  bundle_id TEXT,
  timestamp TIMESTAMPTZ NOT NULL,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX idx_sessions_user_id ON attendance_sessions(user_id);
CREATE INDEX idx_sessions_check_in ON attendance_sessions(check_in_time_utc);
CREATE INDEX idx_sessions_is_closed ON attendance_sessions(is_closed);
CREATE INDEX idx_breaks_session_id ON break_periods(session_id);
CREATE INDEX idx_activities_session_id ON app_activities(session_id);
CREATE INDEX idx_activities_timestamp ON app_activities(timestamp);
```

#### Configure OAuth

1. Go to **Authentication > Providers** in Supabase
2. Enable **Google** provider
3. Add your Google OAuth credentials
4. Add redirect URLs:
   - Desktop: `http://localhost:3000`
   - Web: `https://your-domain.com/auth/callback`

### 5. Google OAuth Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable **Google+ API**
4. Create **OAuth 2.0 Client ID** credentials
5. Configure:
   - **Application type**: Web application
   - **Authorized redirect URIs**:
     - `http://localhost:3000` (desktop)
     - `https://your-supabase-project.supabase.co/auth/v1/callback`
6. Copy Client ID and Secret to `.env`

### 6. Build & Run

#### Desktop (macOS)

```bash
# Build for macOS
flutter build macos --release

# Run in development
flutter run -d macos
```

#### Desktop (Windows)

```bash
# Build for Windows
flutter build windows --release

# Run in development
flutter run -d windows
```

#### Web

```bash
# Build for web
flutter build web --release

# Run local server
flutter run -d chrome
```

---

## Platform Configuration

### macOS Configuration

#### 1. Enable Required Permissions

Edit `macos/Runner/Info.plist`:

```xml
<key>NSAppleEventsUsageDescription</key>
<string>This app needs access to monitor active windows for time tracking.</string>

<key>NSAccessibilityUsageDescription</key>
<string>This app needs accessibility access to track active windows.</string>

<key>LSUIElement</key>
<false/>

<key>LSBackgroundOnly</key>
<false/>
```

#### 2. Code Signing

Enable **App Sandbox** in Xcode:
- Open `macos/Runner.xcodeproj`
- Select Runner target > Signing & Capabilities
- Enable **App Sandbox**
- Check: **Network (Outgoing)**

#### 3. Auto-Start Configuration

The app registers as a login item automatically. Users can disable in:
**System Preferences > Users & Groups > Login Items**

#### 4. Native Code Structure

```swift
// macos/Runner/AppDelegate.swift
- applicationDidFinishLaunching: Setup menu bar, channels
- setupMenuBar: Create status item with icon
- setupPlatformChannel: Handle Flutter method calls

// macos/Runner/ActiveWindowTracker.swift
- startTracking: Monitor NSWorkspace notifications
- getCurrentWindow: Get active app via Accessibility API
- sendActivityEvent: Notify Flutter via method channel

// macos/Runner/RecoveryDialogManager.swift
- showRecoveryDialog: Native alert for session recovery
- handleRecoveryChoice: Return user selection to Flutter
```

### Windows Configuration

#### 1. CMake Configuration

Edit `windows/runner/CMakeLists.txt`:

```cmake
# Add C++ source files
target_sources(${BINARY_NAME} PRIVATE
  "active_window_tracker.cpp"
  "power_monitor.cpp"
  "system_tray.cpp"
  "startup_manager.cpp"
)

# Link Win32 libraries
target_link_libraries(${BINARY_NAME} PRIVATE
  user32.lib
  advapi32.lib
  shell32.lib
)
```

#### 2. Native Code Structure

```cpp
// windows/runner/active_window_tracker.cpp
void StartTracking(): SetWinEventHook for window focus changes
std::string GetActiveWindowTitle(): GetForegroundWindow + GetWindowText

// windows/runner/power_monitor.cpp
LRESULT HandlePowerEvent(WPARAM): Detect sleep/wake via WM_POWERBROADCAST
void RegisterPowerNotifications(): RegisterPowerSettingNotification

// windows/runner/system_tray.cpp
void CreateSystemTray(): Shell_NotifyIcon with custom icon
void ShowContextMenu(): TrackPopupMenu for tray interactions
```

#### 3. Auto-Start Registry

Auto-start managed via registry key:
```
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
Value: "TimeTrak" = "C:\Path\To\time_trak.exe"
```

---

## Development Guide

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# View coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Code Generation

```bash
# Generate build_runner files (if using freezed/json_serializable)
flutter pub run build_runner build --delete-conflicting-outputs
```

### Debugging

#### Enable Logging

Edit [lib/utils/logger.dart](lib/utils/logger.dart):

```dart
class Logger {
  static const bool enableDebugLogs = true; // Set to true

  static void debug(String message) {
    if (enableDebugLogs) {
      print('[DEBUG] $message');
    }
  }
}
```

#### View Native Logs

**macOS:**
```bash
# Console.app filter
log stream --predicate 'processImagePath contains "TimeTrak"' --level debug
```

**Windows:**
```bash
# Visual Studio Debug Output window
# Or use DebugView++ tool
```

#### Supabase Debugging

Check sync status in SQLite:

```sql
SELECT * FROM attendance_sessions WHERE synced_at IS NULL;
```

### State Management Patterns

#### Provider Usage

```dart
// 1. Define provider
class AttendanceProvider extends ChangeNotifier {
  AttendanceState _state = AttendanceState.initial();

  Future<void> checkIn() async {
    // Update state
    _state = _state.copyWith(status: AttendanceStatus.checkedIn);
    notifyListeners(); // Trigger UI rebuild
  }
}

// 2. Register in main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AttendanceProvider()),
  ],
  child: MyApp(),
);

// 3. Consume in widget
class DashboardPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final attendance = Provider.of<AttendanceProvider>(context);
    return Text('Status: ${attendance.state.status}');
  }
}
```

#### Repository Pattern

```dart
// Abstract interface
abstract class ISessionRepository {
  Future<WorkSession> createSession(SessionCreateDto dto);
  Future<WorkSession?> getCurrentSession(String userId);
}

// SQLite implementation (Desktop)
class AttendanceRepository implements ISessionRepository {
  final Database _db;

  @override
  Future<WorkSession> createSession(SessionCreateDto dto) async {
    final id = await _db.insert('attendance_sessions', dto.toMap());
    return WorkSession.fromDb(id, dto);
  }
}

// Supabase implementation (Web)
class SupabaseSessionRepository implements ISessionRepository {
  final SupabaseClient _client;

  @override
  Future<WorkSession> createSession(SessionCreateDto dto) async {
    final response = await _client
        .from('attendance_sessions')
        .insert(dto.toJson())
        .select()
        .single();
    return WorkSession.fromJson(response);
  }
}

// Synced wrapper (Offline-first)
class SyncedAttendanceRepository implements ISessionRepository {
  final AttendanceRepository _localRepo;
  final SupabaseSyncService _syncService;

  @override
  Future<WorkSession> createSession(SessionCreateDto dto) async {
    // Write to local first
    final session = await _localRepo.createSession(dto);

    // Queue background sync
    unawaited(_syncService.syncSession(session.id, 'insert'));

    return session;
  }
}
```

### Adding New Features

#### Example: Add "Lunch Break" Feature

1. **Update Data Model**

Edit [lib/models/attendance_state.dart](lib/models/attendance_state.dart):

```dart
enum BreakType {
  regular,
  lunch, // Add new type
  meeting,
}

class BreakPeriod {
  final String id;
  final BreakType type; // Add field
  // ... other fields
}
```

2. **Update Database Schema**

```sql
-- Add column to Supabase
ALTER TABLE break_periods ADD COLUMN break_type TEXT DEFAULT 'regular';
```

3. **Update Repository**

Edit [lib/services/attendance_repository.dart](lib/services/attendance_repository.dart):

```dart
Future<void> startBreak({
  required String sessionId,
  BreakType type = BreakType.regular,
  String? note,
}) async {
  await _db.insert('break_periods', {
    'session_id': sessionId,
    'break_type': type.name, // Store enum as string
    'break_start_time': DateTime.now().toString(),
    'note': note,
  });
}
```

4. **Update Provider**

Edit [lib/providers/attendance_provider.dart](lib/providers/attendance_provider.dart):

```dart
Future<void> startLunchBreak() async {
  await _repository.startBreak(
    sessionId: _currentSession!.id,
    type: BreakType.lunch,
  );
  notifyListeners();
}
```

5. **Update UI**

```dart
// Add button in dashboard
ElevatedButton(
  onPressed: () => provider.startLunchBreak(),
  child: Text('Start Lunch Break'),
)
```

6. **Add Tests**

```dart
testWidgets('Can start lunch break', (tester) async {
  // Arrange
  final provider = AttendanceProvider();
  await provider.checkIn();

  // Act
  await provider.startLunchBreak();

  // Assert
  expect(provider.currentBreak?.type, BreakType.lunch);
});
```

---

## API Documentation

### Platform Channel API

#### Method Channel: `com.attendance.tracker/system`

**Flutter → Native:**

```dart
// Check if native tracking is available
final bool isAvailable = await platform.invokeMethod('isTrackingAvailable');

// Start activity tracking
await platform.invokeMethod('startTracking');

// Stop activity tracking
await platform.invokeMethod('stopTracking');

// Get current active window
final Map<String, dynamic> window = await platform.invokeMethod('getCurrentWindow');
// Returns: { appName: "Safari", windowTitle: "Google", bundleId: "com.apple.Safari" }
```

**Native → Flutter:**

```dart
// Set up listener
platform.setMethodCallHandler((call) async {
  switch (call.method) {
    case 'onActivityChange':
      final activity = Activity.fromMap(call.arguments);
      _handleActivityChange(activity);
      break;

    case 'onSystemEvent':
      final event = SystemEvent.fromMap(call.arguments);
      _handleSystemEvent(event);
      break;

    case 'onPowerEvent':
      final powerState = call.arguments['state'] as String;
      _handlePowerEvent(powerState); // 'sleep' or 'wake'
      break;
  }
});
```

**Event Structures:**

```dart
// ActivityChangeEvent
{
  'appName': 'Microsoft Excel',
  'windowTitle': 'Monthly Report.xlsx',
  'bundleId': 'com.microsoft.Excel',
  'timestamp': '2024-01-15T14:30:25.000Z',
  'previousDuration': 120, // seconds in previous app
}

// SystemEvent
{
  'type': 'boot', // or 'shutdown', 'sleep', 'wake'
  'timestamp': '2024-01-15T08:00:00.000Z',
}

// PowerEvent
{
  'state': 'wake', // or 'sleep'
  'timestamp': '2024-01-15T09:15:00.000Z',
}
```

### Supabase API Usage

#### Authentication

```dart
// Sign in with OAuth
final response = await Supabase.instance.client.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: 'http://localhost:3000',
);

// Get current session
final session = Supabase.instance.client.auth.currentSession;

// Sign out
await Supabase.instance.client.auth.signOut();
```

#### Database Queries

```dart
// Insert session
final response = await Supabase.instance.client
    .from('attendance_sessions')
    .insert({
      'user_id': userId,
      'check_in_time_utc': DateTime.now().toUtc().toIso8601String(),
      'is_closed': false,
    })
    .select()
    .single();

// Query sessions
final sessions = await Supabase.instance.client
    .from('attendance_sessions')
    .select('*, break_periods(*), app_activities(*)')
    .eq('user_id', userId)
    .gte('check_in_time_utc', startDate.toIso8601String())
    .lte('check_in_time_utc', endDate.toIso8601String())
    .order('check_in_time_utc', ascending: false);

// Update session
await Supabase.instance.client
    .from('attendance_sessions')
    .update({
      'check_out_time_utc': DateTime.now().toUtc().toIso8601String(),
      'is_closed': true,
    })
    .eq('id', sessionId);

// Soft delete
await Supabase.instance.client
    .from('attendance_sessions')
    .update({'is_deleted': true})
    .eq('id', sessionId);
```

#### Real-time Subscriptions

```dart
// Subscribe to session changes
final subscription = Supabase.instance.client
    .from('attendance_sessions')
    .stream(primaryKey: ['id'])
    .eq('user_id', userId)
    .listen((data) {
      // Handle real-time updates
      _refreshSessions(data);
    });

// Unsubscribe
await subscription.cancel();
```

### SQLite Schema

#### Tables

```sql
-- attendance_sessions (Local cache)
CREATE TABLE attendance_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT UNIQUE, -- Supabase UUID
  user_id TEXT NOT NULL,
  check_in_time TEXT NOT NULL,
  check_in_time_utc TEXT NOT NULL,
  check_out_time TEXT,
  check_out_time_utc TEXT,
  is_closed INTEGER DEFAULT 0,
  is_deleted INTEGER DEFAULT 0,
  last_seen_time TEXT,
  continuation_of_session_id TEXT,
  event_source TEXT,
  synced_at TEXT, -- NULL if not synced
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- break_periods
CREATE TABLE break_periods (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT UNIQUE,
  session_id TEXT NOT NULL,
  break_start_time TEXT NOT NULL,
  break_start_time_utc TEXT NOT NULL,
  break_end_time TEXT,
  break_end_time_utc TEXT,
  duration_seconds INTEGER,
  note TEXT,
  synced_at TEXT,
  FOREIGN KEY (session_id) REFERENCES attendance_sessions(uuid)
);

-- app_activities
CREATE TABLE app_activities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT UNIQUE,
  session_id TEXT NOT NULL,
  app_name TEXT NOT NULL,
  window_title TEXT,
  bundle_id TEXT,
  timestamp TEXT NOT NULL,
  closed_at TEXT,
  synced_at TEXT,
  FOREIGN KEY (session_id) REFERENCES attendance_sessions(uuid)
);

-- users (Cached for offline access)
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  name TEXT,
  role TEXT DEFAULT 'member',
  created_at TEXT,
  last_login_at TEXT,
  is_active INTEGER DEFAULT 1
);
```

---

## Troubleshooting

### Common Issues

#### 1. OAuth Fails on Desktop

**Symptom:** Browser opens but redirect fails

**Solutions:**
- Ensure localhost server is running on port 3000
- Check Google OAuth redirect URI includes `http://localhost:3000`
- Verify `.env` has correct `GOOGLE_CLIENT_ID`
- macOS: Check firewall settings allow incoming connections

```bash
# Test localhost server manually
curl http://localhost:3000
```

#### 2. Activity Tracking Not Working

**Symptom:** No activities captured

**macOS Solutions:**
- Grant Accessibility permission:
  1. System Preferences > Security & Privacy > Privacy
  2. Select "Accessibility"
  3. Add Time Trak app
  4. Restart app

**Windows Solutions:**
- Run as Administrator (first launch)
- Check antivirus not blocking window monitoring
- Verify `active_window_tracker.cpp` compiled correctly

#### 3. Sync Failures

**Symptom:** Data not appearing in Supabase

**Solutions:**
- Check network connectivity
- Verify Supabase URL and anon key in `.env`
- Query local SQLite for unsynced items:

```dart
final unsync = await db.query(
  'attendance_sessions',
  where: 'synced_at IS NULL',
);
print('Unsynced sessions: ${unsync.length}');
```

- Check Supabase logs in dashboard
- Verify table permissions (RLS disabled or policies configured)

#### 4. Session Recovery Not Triggering

**Symptom:** No recovery dialog after crash

**Solutions:**
- Verify `last_seen_time` is being updated (every 30s)
- Check boot event is firing in native code
- Test manually:

```dart
// In AttendanceProvider
void testRecovery() {
  _handleBoot(); // Manually trigger recovery check
}
```

- macOS: Check power event threshold (default 15 min)

#### 5. Build Errors

**macOS: CocoaPods Issues**

```bash
cd macos
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
flutter build macos
```

**Windows: CMake Errors**

```bash
flutter clean
cd windows
rmdir /s /q build
cd ..
flutter build windows
```

#### 6. Database Migration Errors

**Symptom:** App crashes on startup with SQLite error

**Solutions:**
- Delete local database (data will re-sync from Supabase):

```bash
# macOS
rm ~/Library/Application\ Support/time_trak/attendance_tracker.db

# Windows
del %APPDATA%\time_trak\attendance_tracker.db
```

- Update schema version in `database_service.dart`
- Implement migration logic in `_onUpgrade()`

### Debug Checklist

- [ ] Flutter doctor passes: `flutter doctor -v`
- [ ] Environment variables loaded: Check `.env` exists
- [ ] Supabase reachable: `curl https://your-project.supabase.co`
- [ ] OAuth configured: Redirect URIs match
- [ ] Permissions granted: Accessibility (macOS), Admin (Windows)
- [ ] Native code compiled: Check build logs
- [ ] Platform channel working: Test with simple method call
- [ ] SQLite initialized: Check database file exists
- [ ] Sync service running: Monitor network requests
- [ ] Logs enabled: Set `Logger.enableDebugLogs = true`

### Getting Help

- **GitHub Issues**: [https://github.com/hetvink/time-tracker/issues](https://github.com/hetvink/time-tracker/issues)
- **Documentation**: Check this README and inline code comments
- **Contact**: Reach out to the development team

---

## License

[Your License Here - e.g., MIT, Apache 2.0, Proprietary]

---

## Contributors

- Development Team - Initial implementation and ongoing maintenance

---

## Changelog

### Recent Updates
- Comprehensive admin dashboard with user activity tracking
- Session recovery and auto-save with smart intervals
- Activity tracking session restoration
- Monthly timesheet and user roles
- Improved duration calculations and last seen time synchronization

---

**Built with Flutter | Powered by Supabase**
