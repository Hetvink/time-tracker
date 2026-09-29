# Core Layer (`lib/core/`)

The **Core Layer** contains global cross-cutting application code, including network synchronization, custom error handling, constants, and utilities used across features.

## Directory Structure

```
lib/core/
├── constants/         # AppConfig, SupabaseConfig, PlatformConfig
├── errors/            # Custom Exceptions, Failures & Error Handlers
├── network/           # SupabaseSyncService, LocalhostServerService
└── utils/             # Logger, Formatters, OAuth Popup Handler
```

## Inventory of Core Components

- **`constants/`**:
  - `app_config.dart`: App versioning, environment flags, and global defaults.
  - `supabase_config.dart`: Cloud API endpoints and anonymous authentication keys.
  - `platform_config.dart`: Native window size, tray icon paths, and desktop constraints.

- **`network/`**:
  - `supabase_sync_service.dart`: Real-time cloud synchronization engine.
  - `localhost_server_service.dart`: Embedded HTTP web server for OAuth login redirects.

- **`utils/`**:
  - `logger.dart`: Structured console logging with log level filtering.
  - `oauth_popup_handler.dart`: Browser popup message listener for web auth flows.
