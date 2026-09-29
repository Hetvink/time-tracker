# Services & Repositories (`lib/services`)

## Overview
The `services` directory implements data persistence, cloud background synchronization, native OS platform channels, session persistence, and authorization repositories.

## File Inventory
- **[database_service.dart](file:///Users/hetvin/developer/time_trak/lib/services/database_service.dart)**: SQLite database engine manager for desktop (`sqflite_common_ffi`), managing local tables, schema migrations, and CRUD operations.
- **[supabase_sync_service.dart](file:///Users/hetvin/developer/time_trak/lib/services/supabase_sync_service.dart)**: Bidirectional background sync engine between local SQLite storage and Supabase cloud PostgreSQL.
- **[attendance_repository.dart](file:///Users/hetvin/developer/time_trak/lib/services/attendance_repository.dart)**: Core repository handling work sessions, check-in/out, breaks, system event triggers, and crash recovery.
- **[app_activity_repository.dart](file:///Users/hetvin/developer/time_trak/lib/services/app_activity_repository.dart)**: Manages local recording, closing, and querying of application activity logs.
- **[platform_channel_service.dart](file:///Users/hetvin/developer/time_trak/lib/services/platform_channel_service.dart)**: Listens to native OS MethodChannel streams (active window focus, system sleep/wake/shutdown events).
- **[auth_service.dart](file:///Users/hetvin/developer/time_trak/lib/services/auth_service.dart)**: Handles Google OAuth authentication flow, PKCE token exchange, session token refresh, and user sign-out.
- **[localhost_server_service.dart](file:///Users/hetvin/developer/time_trak/lib/services/localhost_server_service.dart)**: Local HTTP loopback server for desktop OAuth 2.0 PKCE redirect handling.
- **[admin_repository.dart](file:///Users/hetvin/developer/time_trak/lib/services/admin_repository.dart)**: Admin querying methods for multi-user reports, company-wide timesheets, and activity distribution.
- **[web_attendance_repository.dart](file:///Users/hetvin/developer/time_trak/lib/services/web_attendance_repository.dart)** & **[web_app_activity_repository.dart](file:///Users/hetvin/developer/time_trak/lib/services/web_app_activity_repository.dart)**: Web-specific repositories fetching data directly from Supabase API / Web Cache.

## Clean Architecture Role
- **Layer**: Data Access & Repository Implementation Layer
- **Dependencies**: SQLite, Supabase, `shared_preferences`, platform method channels.
- **Data Flow**: Bridges data sources (local DB / remote cloud / OS events) to presentation providers.
