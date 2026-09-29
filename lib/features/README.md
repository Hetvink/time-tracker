# Features Directory (`lib/features/`)

The **Features Directory** organizes code by domain functionality following **Clean Architecture** principles inside every feature:

```
lib/features/
├── auth/              # User Authentication & Role Authorization
├── tracking/          # Attendance Check-In/Out & App Window Tracking
├── timesheet/         # Timesheets, Timeline Views & Historical Reports
├── admin/             # Organization Admin Panel & User Analytics
└── settings/          # Application Preferences & User Settings
```

## Standard Feature Clean Architecture Schema

Every feature directory follows this standard structure:

```
feature_name/
├── data/
│   ├── models/        # Data Transfer Objects (DTOs) & JSON Mappers
│   ├── datasource/    # Remote API Clients, SQLite Data Sources & Native Drivers
│   └── repository/    # Concrete Repository Implementations
├── domain/
│   ├── entities/      # Core Domain Entities (Framework Independent)
│   ├── repositories/  # Abstract Repository Contracts/Interfaces
│   └── usecases/      # Discrete Business Use Cases
└── presentation/
    ├── providers/     # Provider State Containers (ChangeNotifier)
    ├── screens/       # Full Page/Screen Views
    └── widgets/       # Feature-Specific Visual UI Components
```
