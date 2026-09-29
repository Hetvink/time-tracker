# Infrastructure Module (`lib/infrastructure`)

## Overview
The `infrastructure` directory contains concrete low-level infrastructure drivers, third-party backend SDK wrappers (e.g. Supabase client), local storage engines, and platform channel bindings.

## Subdirectories & Files
- **`supabase/`**: Supabase cloud PostgreSQL client initialization, remote table query abstractions, and real-time subscription channels.

## Clean Architecture Role
- **Layer**: External Infrastructure & Adapters
- **Dependencies**: `supabase_flutter`, `sqflite_common_ffi`, platform OS APIs
- **Data Flow**: Implements external communication channels and feeds normalized data structures back to repository services.
