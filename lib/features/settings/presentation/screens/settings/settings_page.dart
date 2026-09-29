import 'package:flutter/material.dart';

import 'package:time_trak/features/tracking/data/datasource/platform_channel_service.dart';
import 'package:time_trak/features/settings/presentation/providers/preferences_service.dart';

import 'widgets/settings_page.dart';

class SettingsPage extends StatefulWidget {
  final PreferencesService preferencesService;
  final PlatformChannelService platformService;

  const SettingsPage({
    super.key,
    required this.preferencesService,
    required this.platformService,
  });

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

// =============================================================================
// Rows
// =============================================================================

// =============================================================================
// Cards
// =============================================================================

/// Miniature mock of the UI in a given theme.

/// Company membership row in the Account section.
