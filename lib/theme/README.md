# Theme & Styling (`lib/theme`)

## Overview
The `theme` directory defines platform-specific visual themes, color palettes, typographic hierarchies, custom glassmorphism styles, and UI component styling constants.

## File Inventory
- **[macos_theme.dart](file:///Users/hetvin/developer/time_trak/lib/theme/macos_theme.dart)**: Design system tokens for macOS (vibrant dark mode, frosted glass surfaces, subtle borders, SF Pro-style typography).
- **[ios_theme.dart](file:///Users/hetvin/developer/time_trak/lib/theme/ios_theme.dart)**: iOS human interface guidelines theme configuration.

## Clean Architecture Role
- **Layer**: Presentation Design System
- **Dependencies**: `flutter/material.dart`, `glassmorphism`, `liquid_glass_renderer`
- **Data Flow**: Consumed by MaterialApp / CupertinoApp and individual widgets to maintain consistent styling across the application.
